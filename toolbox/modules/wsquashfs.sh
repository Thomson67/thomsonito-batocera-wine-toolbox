#!/bin/bash

WSQ_WINDOWS_DIR="/userdata/roms/windows"
WSQ_TEMPLATES_DIR="$WT_HOME/templates"
WSQ_STATE_DIR="$WT_HOME/state"
WSQ_STATE_FILE="$WSQ_STATE_DIR/wsquashfs-builder.json"
WSQ_HELPER="$WT_ROOT/helpers/wsquashfs_builder.py"
WSQ_SAVE_ROOT="/userdata/saves/windows"
WSQ_CONF="/userdata/system/batocera.conf"
WSQ_BACKUP_DIR="/userdata/system/backups/ultimate-wine-toolbox"

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

wsq_select_template() {
    local -a items=()
    local rows="" path idx=1 choice
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        items+=("$idx" "$(basename "$path")")
        rows+="$path"$'\n'
        idx=$((idx+1))
    done < <(wsq_list_templates)

    if [ "${#items[@]}" -eq 0 ]; then
        msgbox "$(i18n wsq_templates_title)" "$(i18n wsq_templates_none "$WSQ_TEMPLATES_DIR")"
        return 1
    fi

    choice="$(menu_select "$(i18n wsq_templates_title)" "$(i18n wsq_templates_prompt)" "${items[@]}")" || return 1
    sed -n "${choice}p" <<< "$rows"
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
    mkdir -p "$WSQ_BACKUP_DIR"
    python3 - "$WSQ_CONF" "$WSQ_BACKUP_DIR" "$rom_name" "$runner" <<'PY'
import datetime
import os
import re
import shutil
import sys

conf, backup_dir, rom_name, runner = sys.argv[1:5]
os.makedirs(os.path.dirname(conf), exist_ok=True)
if not os.path.exists(conf):
    open(conf, "a", encoding="utf-8").close()

stamp=datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
backup=os.path.join(backup_dir, f"batocera.conf.wsquashfs-{stamp}.bak")
shutil.copy2(conf, backup)

safe_name=rom_name.replace("=", "").replace("#", "")
prefix=f'windows["{safe_name}"].wine-runner='

with open(conf, "r", encoding="utf-8", errors="surrogateescape") as f:
    lines=f.readlines()

lines=[line for line in lines if not line.startswith(prefix)]

if runner != "__SYSTEM__":
    if lines and not lines[-1].endswith("\n"):
        lines[-1]+="\n"
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.append(prefix + runner + "\n")

tmp=conf+".uwt-wsq"
with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.writelines(lines)
os.replace(tmp, conf)
print(backup)
PY
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

wsq_create_new() {
    local source template raw_name game_name target exe_rel runner snapshot backup rom_name
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

        template="$(wsq_select_template)" || return
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
    backup="$(wsq_set_runner_config "$rom_name" "$runner")" || {
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
    command -v batocera-es-swissknife >/dev/null 2>&1 && \
        batocera-es-swissknife --update-gamelists >/dev/null 2>&1 || true

    msgbox "$(i18n wsq_create_title)" \
        "$(i18n wsq_test_ready "$target" "$rom_name" "$backup")"
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

wsq_move_save_data() {
    local prefix="$1" save_rel="$2" game_name="$3"
    local save_abs dest item
    save_abs="$prefix/$save_rel"
    dest="$WSQ_SAVE_ROOT/$game_name"
    mkdir -p "$dest"

    [ -d "$save_abs" ] || return 2
    shopt -s dotglob nullglob
    for item in "$save_abs"/*; do
        if [ -e "$dest/$(basename "$item")" ]; then
            shopt -u dotglob nullglob
            return 3
        fi
    done

    for item in "$save_abs"/*; do
        mv -- "$item" "$dest/"
    done
    shopt -u dotglob nullglob
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

    if ! wsq_move_save_data "$prefix" "$save_rel" "$game_name"; then
        msgbox "$(i18n wsq_save_title)" "$(i18n wsq_save_move_failed "$WSQ_SAVE_ROOT/$game_name")"
        return
    fi

    wsq_write_autorun "$prefix" "$exe_rel" "$save_rel"

    rm -f -- "$snapshot" "$WSQ_STATE_FILE"

    if yesno "$(i18n wsq_create_title)" "$(i18n wsq_build_now)"; then
        archive="${prefix%.wine}.wsquashfs"
        if [ -e "$archive" ]; then
            msgbox "$(i18n wsq_create_title)" "$(i18n wsq_archive_exists "$archive")"
            return
        fi
        if maintenance_squash_wine "$prefix" "$archive"; then
            if yesno_default_no "$(i18n squash_delete_source_title)" \
                "$(i18n squash_delete_source_confirm "$(basename "$prefix")")"; then
                maintenance_delete_wine_dir_symlink_safe "$prefix" || true
            fi
            msgbox "$(i18n wsq_create_title)" "$(i18n wsq_build_done "$archive" "$WSQ_SAVE_ROOT/$game_name")"
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
