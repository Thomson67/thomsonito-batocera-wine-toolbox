#!/bin/bash

WSQ_WINDOWS_DIR="/userdata/roms/windows"
WSQ_TEMPLATES_DIR="$WT_HOME/templates"
WSQ_STATE_DIR="$WT_HOME/state"
WSQ_STATE_FILE="$WSQ_STATE_DIR/wsquashfs-builder.json"
WSQ_HELPER="$WT_ROOT/helpers/wsquashfs_builder.py"
WSQ_SAVE_ROOT="/userdata/saves/windows"
WSQ_CONF="/userdata/system/batocera.conf"

wsq_list_templates() {
    [ -d "$WSQ_TEMPLATES_DIR" ] || return 0
    find "$WSQ_TEMPLATES_DIR" -maxdepth 1 -type f \
        \( -iname '*.prefix' -o -iname '*.wsquashfs' \) -print 2>/dev/null | sort -f
}

wsq_select_source_game() {
    local -a items=()
    local rows="" path base idx=1 choice

    [ -d "$WSQ_WINDOWS_DIR" ] || {
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_windows_missing "$WSQ_WINDOWS_DIR")"
        return 1
    }

    while IFS= read -r path; do
        [ -d "$path" ] || continue
        [ -L "$path" ] && continue
        base="$(basename "$path")"

        items+=("$idx" "$base")
        rows+="$path"$'\n'
        idx=$((idx+1))
    done < <(find "$WSQ_WINDOWS_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -f)

    if [ "${#items[@]}" -eq 0 ]; then
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_no_source_games "$WSQ_WINDOWS_DIR")"
        return 1
    fi

    choice="$(menu_select "$(i18n wsq_create_title)" "$(i18n wsq_source_prompt)" "${items[@]}")" || return 1
    sed -n "${choice}p" <<< "$rows"
}

WSQ_PREFIX_CATALOG_URL="https://raw.githubusercontent.com/Thomson67/batocera-wine-runners/main/prefixes.json"
WSQ_SELECTED_TEMPLATE=""

wsq_default_template_metadata() {
    local catalog_tmp
    catalog_tmp="$(mktemp /tmp/uwt-prefix-catalog.XXXXXX)" || return 1

    if ! download_file "$WSQ_PREFIX_CATALOG_URL" "$catalog_tmp" >/dev/null 2>&1; then
        rm -f -- "$catalog_tmp"
        return 2
    fi

    python3 - "$catalog_tmp" <<'PY'
import json
import os
import sys

path=sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        data=json.load(f)
except Exception:
    raise SystemExit(2)

entries=[x for x in data.get("prefixes", []) if x.get("default") is True]
if len(entries) != 1:
    raise SystemExit(3)

x=entries[0]
required=("name","version","file","size_bytes","download_url","sha256")
if any(k not in x for k in required):
    raise SystemExit(4)

filename=str(x["file"])
if not filename or filename != os.path.basename(filename):
    raise SystemExit(5)

sha=str(x["sha256"]).lower()
if len(sha) != 64:
    raise SystemExit(6)
try:
    int(sha, 16)
except ValueError:
    raise SystemExit(6)

try:
    size=int(x["size_bytes"])
except Exception:
    raise SystemExit(7)
if size <= 0:
    raise SystemExit(7)

for value in (x["name"], x["version"], filename, size, x["download_url"], sha):
    print(value)
PY
    local rc=$?
    rm -f -- "$catalog_tmp"
    return "$rc"
}

wsq_template_terminal_notice() {
    local body="$1"

    # wsq_select_template is called inside command substitution:
    #   template="$(wsq_select_template)"
    # Never write interactive UI to stdout here, otherwise it is captured as
    # part of the selected template path and the terminal appears blank.
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        wt_clear_tty
        {
            printf '==== %s ====\n\n' "$(i18n wsq_templates_download_title)"
            printf '%b\n\n' "$body"
            printf '%s' "$(i18n press_enter)"
        } > /dev/tty
        read -r _ < /dev/tty
        wt_clear_tty
    else
        printf '==== %s ====\n\n%b\n\n%s' \
            "$(i18n wsq_templates_download_title)" "$body" "$(i18n press_enter)" >&2
        read -r _
    fi
}

wsq_install_default_template() {
    local -a meta=()
    local name version filename size url sha size_human free_bytes free_human dest tmp actual_size actual_sha

    while IFS= read -r line; do
        meta+=("$line")
    done < <(wsq_default_template_metadata)

    [ "${#meta[@]}" -eq 6 ] || {
        wsq_template_terminal_notice "$(i18n wsq_template_catalog_failed)"
        return 1
    }

    name="${meta[0]}"
    version="${meta[1]}"
    filename="${meta[2]}"
    size="${meta[3]}"
    url="${meta[4]}"
    sha="${meta[5]}"
    size_human="$(human_bytes "$size")"

    free_bytes="$(df -Pk "$WT_HOME" 2>/dev/null | awk 'NR==2 {print $4 * 1024}' | cut -d. -f1)"
    case "$free_bytes" in ''|*[!0-9]*) free_bytes=0 ;; esac
    free_human="$(human_bytes "$free_bytes")"

    local download_choice
    download_choice="$(menu_select "$(i18n wsq_templates_download_title)" \
        "$(i18n wsq_templates_download_prompt "$name" "$version" "$size_human" "$WSQ_TEMPLATES_DIR" "$free_human")" \
        "1" "$(i18n yes)" \
        "0" "$(i18n no)")" || return 1
    [ "$download_choice" = "1" ] || return 1

    if [ "$free_bytes" -gt 0 ] && [ "$free_bytes" -lt "$size" ]; then
        wsq_template_terminal_notice "$(i18n wsq_template_no_space "$size_human" "$free_human")"
        return 1
    fi

    mkdir -p "$WSQ_TEMPLATES_DIR" || {
        wsq_template_terminal_notice "$(i18n wsq_template_dir_failed "$WSQ_TEMPLATES_DIR")"
        return 1
    }

    dest="$WSQ_TEMPLATES_DIR/$filename"
    tmp="$dest.download-$$"
    rm -f -- "$tmp"

    if [ -w /dev/tty ]; then
        wt_clear_tty
        {
            printf '==== %s ====\n\n' "$(i18n wsq_templates_download_title)"
            printf '%b\n\n' "$(i18n wsq_template_downloading "$name" "$size_human")"
        } > /dev/tty
    fi

    if ! download_file "$url" "$tmp" 2>/dev/tty; then
        rm -f -- "$tmp"
        wsq_template_terminal_notice "$(i18n wsq_template_download_failed)"
        return 1
    fi

    actual_size="$(wc -c < "$tmp" 2>/dev/null | tr -d '[:space:]')"
    if [ "$actual_size" != "$size" ]; then
        rm -f -- "$tmp"
        wsq_template_terminal_notice "$(i18n wsq_template_size_failed "$size" "$actual_size")"
        return 1
    fi

    actual_sha="$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')"
    if [ "$actual_sha" != "$sha" ]; then
        rm -f -- "$tmp"
        wsq_template_terminal_notice "$(i18n wsq_template_checksum_failed)"
        return 1
    fi

    if ! mv -f -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        wsq_template_terminal_notice "$(i18n wsq_template_install_failed)"
        return 1
    fi

    wt_log "WSquashFS: default prefix template installed: $dest ($size_human, version $version)"
    return 0
}

wsq_select_template() {
    local -a items=()
    local rows="" path idx=1 choice

    WSQ_SELECTED_TEMPLATE=""

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        items+=("$idx" "$(basename "$path")")
        rows+="$path"$'\n'
        idx=$((idx+1))
    done < <(wsq_list_templates)

    if [ "${#items[@]}" -eq 0 ]; then
        wsq_install_default_template || return 1

        items=()
        rows=""
        idx=1
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            items+=("$idx" "$(basename "$path")")
            rows+="$path"$'\n'
            idx=$((idx+1))
        done < <(wsq_list_templates)

        [ "${#items[@]}" -gt 0 ] || {
            wsq_template_terminal_notice "$(i18n wsq_templates_none "$WSQ_TEMPLATES_DIR")"
            return 1
        }
    fi

    choice="$(menu_select "$(i18n wsq_templates_title)" "$(i18n wsq_templates_prompt)" "${items[@]}")" || return 1
    WSQ_SELECTED_TEMPLATE="$(sed -n "${choice}p" <<< "$rows")"
    [ -n "$WSQ_SELECTED_TEMPLATE" ]
}

wsq_clean_name() {
    local name="$1"
    python3 "$WSQ_HELPER" clean-name "$name"
}

wsq_prepare_prefix() {
    local source="$1" template="$2" game_name="$3" target="$4"
    local tmp parent
    parent="$(dirname "$target")"
    tmp="$parent/.uwt-prefix-$$"

    [ ! -e "$target" ] || return 2
    rm -rf -- "$tmp"

    if ! unsquashfs -f -q -no-xattrs -d "$tmp" "$template"; then
        rm -rf -- "$tmp"
        return 3
    fi

    [ -d "$tmp/drive_c" ] || {
        rm -rf -- "$tmp"
        return 4
    }

    if ! mv -- "$tmp" "$target"; then
        rm -rf -- "$tmp"
        return 5
    fi

    mkdir -p "$target/drive_c/game" "$target/drive_c/users/steamuser"

    local item base
    shopt -s dotglob nullglob
    for item in "$source"/*; do
        base="$(basename "$item")"
        [ "$item" = "$target" ] && continue
        if ! mv -- "$item" "$target/drive_c/game/"; then
            # All game items already moved came from this source directory and
            # drive_c/game was created empty above. Roll them back using
            # same-filesystem renames so a partial preparation does not split
            # a very large game between two locations.
            local rollback
            for rollback in "$target/drive_c/game"/*; do
                mv -- "$rollback" "$source/" 2>/dev/null || true
            done
            shopt -u dotglob nullglob
            rm -rf -- "$target"
            return 6
        fi
    done
    shopt -u dotglob nullglob

    rmdir "$source" 2>/dev/null || true

    if [ -e "$target/drive_c/users/root" ] || [ -L "$target/drive_c/users/root" ]; then
        if [ -L "$target/drive_c/users/root" ]; then
            rm -f -- "$target/drive_c/users/root"
        elif [ -d "$target/drive_c/users/root" ]; then
            rm -rf -- "$target/drive_c/users/root"
        else
            rm -f -- "$target/drive_c/users/root"
        fi
    fi
    ln -s steamuser "$target/drive_c/users/root"
}

wsq_select_executable() {
    local prefix="$1"
    local -a items=()
    local rows="" line score rel idx=1 choice
    while IFS=$'\t' read -r score rel; do
        [ -n "$rel" ] || continue
        items+=("$idx" "[$score] $rel")
        rows+="$rel"$'\n'
        idx=$((idx+1))
    done < <(python3 "$WSQ_HELPER" exes "$prefix")

    if [ "${#items[@]}" -eq 0 ]; then
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_no_executable)"
        return 1
    fi

    choice="$(menu_select "$(i18n wsq_executable_title)" "$(i18n wsq_executable_prompt)" "${items[@]}")" || return 1
    sed -n "${choice}p" <<< "$rows"
}

wsq_write_autorun() {
    local prefix="$1" exe_rel="$2" savedir="${3:-}"
    local exe_dir exe_name tmp
    exe_dir="$(dirname "$exe_rel")"
    exe_name="$(basename "$exe_rel")"
    [ "$exe_dir" = "." ] && exe_dir=""

    tmp="$prefix/autorun.cmd.uwt-tmp"
    {
        [ -n "$savedir" ] && printf 'SAVEDIR=%s/\n' "${savedir%/}"
        printf 'DIR=%s\n' "$exe_dir"
        printf 'CMD="%s"\n' "$exe_name"
    } > "$tmp"
    mv -f -- "$tmp" "$prefix/autorun.cmd"
}

wsq_runner_candidates() {
    local path name
    if [ -d "/userdata/system/wine/custom" ]; then
        while IFS= read -r path; do
            [ -d "$path" ] || continue
            name="$(basename "$path")"
            case "$name" in
                *-UMU|*-umu) printf 'umu\t%s\n' "$name" ;;
            esac
        done < <(find /userdata/system/wine/custom -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -f)
    fi
    printf 'system\t__SYSTEM__\n'
    if [ -d "/userdata/system/wine/custom" ]; then
        while IFS= read -r path; do
            [ -d "$path" ] || continue
            name="$(basename "$path")"
            case "$name" in
                *-UMU|*-umu) continue ;;
            esac
            printf 'custom\t%s\n' "$name"
        done < <(find /userdata/system/wine/custom -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -f)
    fi
}

wsq_select_runner() {
    local -a items=()
    local rows="" kind name idx=1 choice label
    while IFS=$'\t' read -r kind name; do
        [ -n "$name" ] || continue
        if [ "$name" = "__SYSTEM__" ]; then
            label="$(i18n wsq_runner_system)"
        elif [ "$kind" = "umu" ]; then
            label="$name  [UMU]"
        else
            label="$name"
        fi
        items+=("$idx" "$label")
        rows+="$name"$'\n'
        idx=$((idx+1))
    done < <(wsq_runner_candidates)

    choice="$(menu_select "$(i18n wsq_runner_title)" "$(i18n wsq_runner_prompt)" "${items[@]}")" || return 1
    sed -n "${choice}p" <<< "$rows"
}

wsq_set_runner_config() {
    local rom_name="$1" runner="$2"
    python3 - "$WSQ_CONF" "$rom_name" "$runner" <<'PY'
import os
import sys

conf, rom_name, runner = sys.argv[1:4]
os.makedirs(os.path.dirname(conf), exist_ok=True)
if not os.path.exists(conf):
    open(conf, "a", encoding="utf-8").close()

safe_name=rom_name.replace("=", "").replace("#", "")
canonical_prefix = f'windows["{safe_name}"].wine-runner='

with open(conf, "r", encoding="utf-8", errors="surrogateescape") as f:
    lines=f.readlines()

def keep_line(line):
    stripped=line.lstrip()
    return not stripped.startswith(canonical_prefix)

lines=[line for line in lines if keep_line(line)]

if runner != "__SYSTEM__":
    if lines and not lines[-1].endswith("\n"):
        lines[-1]+="\n"
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.append(canonical_prefix + runner + "\n")

tmp=conf+".uwt-wsq"
with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.writelines(lines)
os.replace(tmp, conf)
PY
}

wsq_finalize_runner_config() {
    local game_name="$1" runner="$2"
    local final_rom="${game_name}.wsquashfs"
    wsq_set_runner_config "$final_rom" "$runner"
}

wsq_save_state() {
    local prefix="$1" game_name="$2" snapshot="$3" exe_rel="$4" runner="$5"
    mkdir -p "$WSQ_STATE_DIR"
    python3 - "$WSQ_STATE_FILE" "$prefix" "$game_name" "$snapshot" "$exe_rel" "$runner" <<'PY'
import json, sys
path, prefix, game, snapshot, exe, runner = sys.argv[1:7]
with open(path, "w", encoding="utf-8") as f:
    json.dump({
        "prefix": prefix,
        "game_name": game,
        "snapshot": snapshot,
        "exe_rel": exe,
        "runner": runner,
    }, f, ensure_ascii=False, indent=2)
PY
}

wsq_state_value() {
    local key="$1"
    python3 - "$WSQ_STATE_FILE" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data=json.load(f)
print(data.get(sys.argv[2], ""))
PY
}

wsq_refresh_emulationstation_games() {
    local url="http://127.0.0.1:1234/reloadgames"

    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 5 "$url" >/dev/null 2>&1 && return 0
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 5 -O /dev/null "$url" >/dev/null 2>&1 && return 0
    fi

    wt_log "WSquashFS: unable to request EmulationStation gamelist reload via $url"
    return 1
}

wsq_restart_emulationstation_deferred() {
    mkdir -p "$WSQ_STATE_DIR"
    : > "$WSQ_STATE_DIR/restart-es.request"
    return 0
}

wsq_request_game_launch() {
    local rom="$1"
    mkdir -p "$WSQ_STATE_DIR"
    printf '%s\n' "$rom" > "$WSQ_STATE_DIR/launch-game.request"
    return 0
}

wsq_create_new() {
    local source template raw_name game_name target exe_rel runner snapshot rom_name
    command -v unsquashfs >/dev/null 2>&1 || {
        msgbox "$(i18n wsq_create_title)" "$(i18n squash_tools_missing)"
        return
    }

    source="$(wsq_select_source_game)" || return
    [ -d "$source" ] || {
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_source_invalid "$source")"
        return
    }

    source="$(readlink -f -- "$source" 2>/dev/null || printf '%s' "$source")"
    local windows_root
    windows_root="$(readlink -f -- "$WSQ_WINDOWS_DIR" 2>/dev/null || printf '%s' "$WSQ_WINDOWS_DIR")"

    if [ "$source" = "$windows_root" ]; then
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_source_root_forbidden "$source")"
        return
    fi

    if [[ "$(basename "$source")" == *.wine ]]; then
        target="$source"
        raw_name="$(basename "$source")"
        raw_name="${raw_name%.wine}"
        game_name="$(wsq_clean_name "$raw_name")"
        [ -n "$game_name" ] || game_name="$raw_name"

        [ -d "$target/drive_c" ] || {
            msgbox "$(i18n wsq_create_title)" "$(i18n wsq_wine_invalid "$target")"
            return
        }
    else
        if find "$source" -mindepth 1 -maxdepth 1 \
            \( -type d \( -iname '*.wine' -o -iname '*.pc' \) -o -type f -iname '*.wsquashfs' \) \
            -print -quit 2>/dev/null | grep -q .; then
            msgbox "$(i18n wsq_create_title)" "$(i18n wsq_source_contains_games "$source")"
            return
        fi

        wsq_select_template || return
        template="$WSQ_SELECTED_TEMPLATE"
        raw_name="$(basename "$source")"
        raw_name="${raw_name%.pc}"
        game_name="$(wsq_clean_name "$raw_name")"
        [ -n "$game_name" ] || game_name="$raw_name"
        target="$(dirname "$source")/$game_name.wine"

        [ ! -e "$target" ] || {
            msgbox "$(i18n wsq_create_title)" "$(i18n wsq_target_exists "$target")"
            return
        }

        yesno_default_no "$(i18n wsq_create_title)" \
            "$(i18n wsq_move_confirm "$source" "$template" "$target")" || return

        if ! wsq_prepare_prefix "$source" "$template" "$game_name" "$target"; then
            msgbox "$(i18n wsq_create_title)" "$(i18n wsq_prepare_failed "$target")"
            return
        fi
    fi

    exe_rel="$(wsq_select_executable "$target")" || {
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_prefix_kept "$target")"
        return
    }
    wsq_write_autorun "$target" "$exe_rel"

    runner="$(wsq_select_runner)" || {
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_prefix_kept "$target")"
        return
    }

    rom_name="$(basename "$target")"
    wsq_set_runner_config "$rom_name" "$runner" || {
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_runner_config_failed)"
        return
    }

    mkdir -p "$WSQ_STATE_DIR"
    snapshot="$WSQ_STATE_DIR/wsquashfs-before-$$.json"
    if ! python3 "$WSQ_HELPER" snapshot "$target" "$snapshot"; then
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_snapshot_failed)"
        return
    fi

    wsq_save_state "$target" "$game_name" "$snapshot" "$exe_rel" "$runner"

    msgbox "$(i18n wsq_create_title)" \
        "$(i18n wsq_test_ready "$target" "$rom_name")"

    wsq_request_game_launch "$target" || true
    wsq_restart_emulationstation_deferred || true
    exit 0
}

wsq_select_save_candidate() {
    local prefix="$1" snapshot="$2"
    local -a items=()
    local rows="" score count rel reason idx=1 choice
    while IFS=$'\t' read -r score count rel reason; do
        [ -n "$rel" ] || continue
        items+=("$idx" "[$score] $rel  ($count)")
        rows+="$rel"$'\n'
        idx=$((idx+1))
    done < <(python3 "$WSQ_HELPER" diff "$prefix" "$snapshot")

    if [ "${#items[@]}" -eq 0 ]; then
        msgbox "$(i18n wsq_resume_title)" "$(i18n wsq_no_save_candidates)"
        return 1
    fi

    choice="$(menu_select "$(i18n wsq_save_title)" "$(i18n wsq_save_prompt)" "${items[@]}")" || return 1
    sed -n "${choice}p" <<< "$rows"
}

wsq_save_destination_prepare() {
    local dest="$1"
    local choice backup stamp

    if [ ! -e "$dest" ]; then
        mkdir -p "$dest"
        return 0
    fi

    [ -d "$dest" ] && [ ! -L "$dest" ] || return 4

    choice="$(menu_select "$(i18n wsq_save_conflict_title)" \
        "$(i18n wsq_save_conflict_body "$dest")" \
        "1" "$(i18n wsq_save_conflict_backup)" \
        "2" "$(i18n wsq_save_conflict_replace)" \
        "0" "$(i18n cancel)")" || return 10

    case "$choice" in
        1)
            stamp="$(date '+%Y%m%d-%H%M%S')"
            backup="${dest}.backup-${stamp}"
            while [ -e "$backup" ]; do
                sleep 1
                stamp="$(date '+%Y%m%d-%H%M%S')"
                backup="${dest}.backup-${stamp}"
            done
            if ! mv -- "$dest" "$backup"; then
                return 5
            fi
            mkdir -p "$dest" || {
                mv -- "$backup" "$dest" 2>/dev/null || true
                return 6
            }
            WSQ_LAST_SAVE_BACKUP="$backup"
            return 0
            ;;
        2)
            yesno_default_no "$(i18n wsq_save_conflict_title)" \
                "$(i18n wsq_save_replace_confirm "$dest")" || return 10
            rm -rf -- "$dest" || return 7
            mkdir -p "$dest" || return 8
            WSQ_LAST_SAVE_BACKUP=""
            return 0
            ;;
        0|"")
            return 10
            ;;
    esac

    return 10
}

wsq_move_save_data() {
    local prefix="$1" save_rel="$2" game_name="$3"
    local save_abs dest item
    save_abs="$prefix/$save_rel"
    dest="$WSQ_SAVE_ROOT/$game_name"
    WSQ_LAST_SAVE_BACKUP=""

    [ -d "$save_abs" ] || return 2

    if ! wsq_save_destination_prepare "$dest"; then
        return $?
    fi

    shopt -s dotglob nullglob
    for item in "$save_abs"/*; do
        if ! mv -- "$item" "$dest/"; then
            shopt -u dotglob nullglob
            return 9
        fi
    done
    shopt -u dotglob nullglob
}

wsq_cleanup_internal_savedir() {
    local prefix="$1" save_rel="$2"
    local save_abs prefix_real save_real parent_real

    save_rel="${save_rel%/}"
    [ -n "$save_rel" ] || return 1

    prefix_real="$(readlink -f -- "$prefix" 2>/dev/null || true)"
    [ -n "$prefix_real" ] || return 1

    save_abs="$prefix/$save_rel"

    # SAVEDIR must remain an internal path of this prefix. Never follow or
    # remove anything outside the prefix.
    parent_real="$(readlink -f -- "$(dirname "$save_abs")" 2>/dev/null || true)"
    case "$parent_real" in
        "$prefix_real"|"$prefix_real"/*) ;;
        *) return 1 ;;
    esac

    # A symlink is never allowed in the final archive. Replace it with a real,
    # empty directory so an extracted .pc/.wine remains directly runnable.
    if [ -L "$save_abs" ]; then
        rm -f -- "$save_abs" || return 1
        mkdir -p -- "$save_abs" || return 1
        return 0
    fi

    # If the path disappeared after moving the save data, recreate it as a
    # real empty directory for portability after extraction.
    if [ ! -e "$save_abs" ]; then
        mkdir -p -- "$save_abs" || return 1
        return 0
    fi

    [ -d "$save_abs" ] || return 1
    save_real="$(readlink -f -- "$save_abs" 2>/dev/null || true)"
    case "$save_real" in
        "$prefix_real"/*) ;;
        *) return 1 ;;
    esac

    # Never hide unexpected data inside the final archive. The save contents
    # must already have been moved to /userdata/saves/windows/<game>.
    if find "$save_abs" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        return 2
    fi

    # Keep the real empty directory in the prefix. This makes an extracted
    # archive usable as .pc/.wine without requiring Batocera to recreate it.
    return 0
}

wsq_prepare_existing_archive() {
    local archive="$1"
    local choice stamp backup

    WSQ_LAST_ARCHIVE_BACKUP=""

    [ -e "$archive" ] || return 0
    [ -f "$archive" ] && [ ! -L "$archive" ] || return 4

    choice="$(menu_select "$(i18n wsq_archive_conflict_title)" \
        "$(i18n wsq_archive_conflict_body "$archive")" \
        "1" "$(i18n wsq_archive_conflict_backup)" \
        "2" "$(i18n wsq_archive_conflict_replace)" \
        "0" "$(i18n cancel)")" || return 10

    case "$choice" in
        1)
            stamp="$(date '+%Y%m%d-%H%M%S')"
            case "$archive" in
                *.wsquashfs) backup="${archive%.wsquashfs}.backup-${stamp}.wsquashfs" ;;
                *) backup="${archive}.backup-${stamp}" ;;
            esac
            while [ -e "$backup" ]; do
                sleep 1
                stamp="$(date '+%Y%m%d-%H%M%S')"
                case "$archive" in
                    *.wsquashfs) backup="${archive%.wsquashfs}.backup-${stamp}.wsquashfs" ;;
                    *) backup="${archive}.backup-${stamp}" ;;
                esac
            done
            mv -- "$archive" "$backup" || return 5
            WSQ_LAST_ARCHIVE_BACKUP="$backup"
            wt_log "WSquashFS: existing archive backed up: $archive -> $backup"
            return 0
            ;;
        2)
            # Keep the current archive in place while mksquashfs builds and
            # validates a temporary file. maintenance_squash_wine() replaces
            # the destination only after the new archive has passed validation.
            wt_log "WSquashFS: existing archive will be atomically replaced after validation: $archive"
            return 0
            ;;
        0|"")
            return 10
            ;;
    esac

    return 10
}

wsq_post_build_menu() {
    local choice
    choice="$(menu_select "$(i18n wsq_post_title)" "$(i18n wsq_post_prompt)" \
        "1" "$(i18n wsq_post_new)" \
        "2" "$(i18n wsq_post_toolbox)" \
        "3" "$(i18n wsq_post_es)")" || return 20

    case "$choice" in
        1)
            wsq_create_new
            return 0
            ;;
        2)
            return 0
            ;;
        3|"")
            return 20
            ;;
    esac
}

wsq_resume_build() {
    local prefix game_name snapshot exe_rel runner save_rel dest archive
    [ -s "$WSQ_STATE_FILE" ] || {
        msgbox "$(i18n wsq_resume_title)" "$(i18n wsq_no_pending)"
        return
    }

    prefix="$(wsq_state_value prefix)"
    game_name="$(wsq_state_value game_name)"
    snapshot="$(wsq_state_value snapshot)"
    exe_rel="$(wsq_state_value exe_rel)"
    runner="$(wsq_state_value runner)"

    [ -d "$prefix" ] && [ -s "$snapshot" ] || {
        msgbox "$(i18n wsq_resume_title)" "$(i18n wsq_pending_invalid)"
        return
    }

    save_rel="$(wsq_select_save_candidate "$prefix" "$snapshot")" || return

    yesno_default_no "$(i18n wsq_save_title)" \
        "$(i18n wsq_save_confirm "$save_rel" "$WSQ_SAVE_ROOT/$game_name")" || return

    wsq_move_save_data "$prefix" "$save_rel" "$game_name"
    local move_rc=$?
    if [ "$move_rc" -ne 0 ]; then
        if [ "$move_rc" -eq 10 ]; then
            return
        fi
        msgbox "$(i18n wsq_save_title)" "$(i18n wsq_save_move_failed "$WSQ_SAVE_ROOT/$game_name")"
        return
    fi

    wsq_write_autorun "$prefix" "$exe_rel" "$save_rel"

    if [ -n "${WSQ_LAST_SAVE_BACKUP:-}" ]; then
        msgbox "$(i18n wsq_save_title)" "$(i18n wsq_save_backup_done "$WSQ_LAST_SAVE_BACKUP")"
    fi

    rm -f -- "$snapshot" "$WSQ_STATE_FILE"

    if yesno "$(i18n wsq_create_title)" "$(i18n wsq_build_now)"; then
        archive="${prefix%.wine}.wsquashfs"
        wsq_prepare_existing_archive "$archive"
        local archive_rc=$?
        if [ "$archive_rc" -ne 0 ]; then
            case "$archive_rc" in
                10)
                    return
                    ;;
                4)
                    msgbox "$(i18n wsq_archive_conflict_title)" "$(i18n wsq_archive_conflict_invalid "$archive")"
                    ;;
                5)
                    msgbox "$(i18n wsq_archive_conflict_title)" "$(i18n wsq_archive_backup_failed "$archive")"
                    ;;
                *)
                    msgbox "$(i18n wsq_archive_conflict_title)" "$(i18n wsq_archive_conflict_failed "$archive")"
                    ;;
            esac
            return
        fi
        wsq_cleanup_internal_savedir "$prefix" "$save_rel"
        local cleanup_rc=$?
        if [ "$cleanup_rc" -ne 0 ]; then
            if [ "$cleanup_rc" -eq 2 ]; then
                msgbox "$(i18n wsq_create_title)" "$(i18n wsq_savedir_not_empty "$prefix/$save_rel")"
            else
                msgbox "$(i18n wsq_create_title)" "$(i18n wsq_savedir_cleanup_failed "$prefix/$save_rel")"
            fi
            return
        fi

        if maintenance_squash_wine "$prefix" "$archive"; then
            wsq_finalize_runner_config "$game_name" "$runner" || {
                msgbox "$(i18n wsq_create_title)" "$(i18n wsq_runner_finalize_failed "$archive")"
                return
            }

            if [ -n "${WSQ_LAST_ARCHIVE_BACKUP:-}" ]; then
                msgbox "$(i18n wsq_archive_conflict_title)" \
                    "$(i18n wsq_archive_backup_done "$WSQ_LAST_ARCHIVE_BACKUP")"
            fi

            if yesno_default_no "$(i18n squash_delete_source_title)" \
                "$(i18n squash_delete_source_confirm "$(basename "$prefix")")"; then
                maintenance_delete_wine_dir_symlink_safe "$prefix" || true
            fi
            msgbox "$(i18n wsq_create_title)" "$(i18n wsq_build_done "$archive" "$WSQ_SAVE_ROOT/$game_name")"
            wsq_restart_emulationstation_deferred || true
            wsq_post_build_menu
            return $?
        else
            msgbox "$(i18n wsq_create_title)" "$(i18n wsq_build_failed)"
        fi
    else
        msgbox "$(i18n wsq_create_title)" "$(i18n wsq_ready_to_squash "$prefix")"
    fi
}

wsq_templates_info() {
    msgbox "$(i18n wsq_templates_title)" "$(i18n wsq_templates_info "$WSQ_TEMPLATES_DIR")"
}

wsquashfs_menu() {
    while true; do
        local choice pending=""
        [ -s "$WSQ_STATE_FILE" ] && pending="$(i18n wsq_pending_marker)"
        choice="$(menu_select "$(i18n wsq_title)" "$(i18n wsq_intro)" \
            "1" "$(i18n wsq_create_action)" \
            "2" "$(i18n wsq_resume_action) $pending" \
            "3" "$(i18n squash_wine)" \
            "4" "$(i18n unsquash_wine)" \
            "5" "$(i18n wsq_templates_title)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) wsq_create_new ;;
            2) wsq_resume_build ;;
            3) maintenance_select_and_squash ;;
            4) maintenance_select_and_unsquash ;;
            5) wsq_templates_info ;;
            0|"") return ;;
        esac
    done
}
