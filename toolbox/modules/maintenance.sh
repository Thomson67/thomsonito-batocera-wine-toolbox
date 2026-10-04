#!/bin/bash

BOTTLES_ROOT="/userdata/system/wine-bottles/windows"
WINDOWS_ROMS_DIR="/userdata/roms/windows"
WT_LOG_DIR="/userdata/system/logs/thomsonito-wine-toolbox"
BOTTLES_CACHE="/tmp/wt-bottles-cache.tsv"

maintenance_dir_kib() {
    local path="$1"
    du -sk -- "$path" 2>/dev/null | awk '{print $1+0}'
}

maintenance_kib_human() {
    local kib="${1:-0}"
    human_bytes "$((kib * 1024))"
}

maintenance_bottles_cache_invalidate() {
    rm -f "$BOTTLES_CACHE" 2>/dev/null || true
}

maintenance_bottles_cache_build() {
    local tmp
    tmp="$(mktemp /tmp/wt-bottles-scan.XXXXXX)" || return 1

    python3 - "$BOTTLES_ROOT" "$WINDOWS_ROMS_DIR" > "$tmp" <<'PY'
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
roms = Path(sys.argv[2])

if not root.is_dir():
    raise SystemExit

def is_runner_container(p: Path) -> bool:
    try:
        if (p / "default-prefix").is_dir() or (p / "default-settings").exists():
            return True
        return any(c.is_dir() and c.name.endswith(".wine") for c in p.iterdir())
    except OSError:
        return False

SUPPORTED_ROM_EXTENSIONS = (".pc", ".exe", ".wine", ".wsquashfs", ".wtgz")

game_names = set()
if roms.is_dir():
    try:
        for p in roms.iterdir():
            lower = p.name.casefold()
            if lower.endswith(SUPPORTED_ROM_EXTENSIONS):
                game_names.add(lower)
    except OSError:
        pass

records = []

try:
    roots = sorted((p for p in root.iterdir() if p.is_dir()), key=lambda p: p.name.lower())
except OSError:
    roots = []

# Batocera 43+ : <runner>/<rom>.wine
for runner in roots:
    if not is_runner_container(runner):
        continue
    try:
        children = sorted((p for p in runner.iterdir() if p.is_dir()), key=lambda p: p.name.lower())
    except OSError:
        continue
    for bottle in children:
        if bottle.name in {"default-prefix", "default-settings"}:
            continue
        if not bottle.name.endswith(".wine"):
            continue
        records.append(("v43", runner.name, bottle.name, str(bottle)))

# Legacy pre-v43 : direct children of wine-bottles/windows.
for bottle in roots:
    if bottle.name in {"default-prefix", "default-settings"}:
        continue
    if is_runner_container(bottle):
        continue
    records.append(("legacy", "-", bottle.name, str(bottle)))

def bottle_has_game(kind: str, name: str) -> bool:
    # Batocera 43+ appends ".wine" to the complete ROM filename.
    # Example:
    #   ROM    : Out of Sight.pc
    #   Bottle : Out of Sight.pc.wine
    #
    # The ROM extension is significant and must not be normalized away.
    if kind == "v43" and name.lower().endswith(".wine"):
        rom_name = name[:-5]
    else:
        rom_name = name

    return rom_name.casefold() in game_names

# One du process per batch instead of one process per bottle.
sizes = {}
paths = [r[3] for r in records]
for pos in range(0, len(paths), 200):
    batch = paths[pos:pos + 200]
    if not batch:
        continue
    try:
        proc = subprocess.run(
            ["du", "-sk", "--", *batch],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        continue

    for line in proc.stdout.splitlines():
        try:
            size, path = line.split("\t", 1)
            sizes[path] = int(size)
        except (ValueError, TypeError):
            continue

for kind, runner, name, path in records:
    orphan = "0" if bottle_has_game(kind, name) else "1"
    print("\t".join((kind, runner, name, path, str(sizes.get(path, 0)), orphan)))
PY

    mv -f "$tmp" "$BOTTLES_CACHE"
}

maintenance_bottle_records() {
    [ -s "$BOTTLES_CACHE" ] || maintenance_bottles_cache_build || return 1
    cat "$BOTTLES_CACHE"
}

maintenance_bottle_count() {
    maintenance_bottle_records | awk 'END{print NR+0}'
}

maintenance_bottle_total_kib() {
    maintenance_bottle_records | awk -F '\t' '{s+=$5} END{print s+0}'
}

maintenance_orphan_count() {
    maintenance_bottle_records | awk -F '\t' '$6==1 {n++} END{print n+0}'
}

maintenance_orphan_total_kib() {
    maintenance_bottle_records | awk -F '\t' '$6==1 {s+=$5} END{print s+0}'
}

maintenance_bottles_overview() {
    local count total
    count="$(maintenance_bottle_count)"
    total="$(maintenance_bottle_total_kib)"
    msgbox "$(i18n bottles_title)" "$(i18n bottles_overview "$count" "$(maintenance_kib_human "$total")" "$BOTTLES_ROOT")"
}

maintenance_delete_selected_bottles() {
    local mode="${1:-all}"
    local -a items=()
    local rows="" kind runner name path kib orphan label idx=1 count=0
    local selected="" id line selected_paths="" selected_names="" total=0 failures=0

    while IFS=$'\t' read -r kind runner name path kib orphan; do
        [ -n "$path" ] || continue

        if [ "$mode" = "orphans" ] && [ "$orphan" != "1" ]; then
            continue
        fi

        if [ "$kind" = "v43" ]; then
            label="$(i18n bottles_item_v43 "$name" "$runner" "$(maintenance_kib_human "$kib")")"
        else
            label="$(i18n bottles_item_legacy "$name" "$(maintenance_kib_human "$kib")")"
        fi

        items+=("$idx" "$label" "off")
        rows+="$path"$'\t'"$name"$'\t'"$kib"$'\n'
        idx=$((idx+1))
        count=$((count+1))
    done < <(maintenance_bottle_records)

    if [ "$count" -eq 0 ]; then
        if [ "$mode" = "orphans" ]; then
            msgbox "$(i18n bottles_orphans)" "$(i18n bottles_no_orphans)"
        else
            msgbox "$(i18n bottles_title)" "$(i18n bottles_none)"
        fi
        return
    fi

    if [ "$mode" = "orphans" ]; then
        selected="$(checklist_select "$(i18n bottles_orphans)" "$(i18n bottles_orphans_prompt)" "${items[@]}")" || return
    else
        yesno "$(i18n bottles_warning_title)" "$(i18n bottles_warning)" || return
        selected="$(checklist_select "$(i18n bottles_delete_selected)" "$(i18n bottles_select_prompt)" "${items[@]}")" || return
    fi

    [ -n "$selected" ] || return

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        line="$(sed -n "${id}p" <<< "$rows")"
        IFS=$'\t' read -r path name kib <<< "$line"
        [ -n "$path" ] || continue
        selected_paths+="$path"$'\n'
        selected_names+="• $name"$'\n'
        total=$((total + kib))
    done <<< "$selected"

    [ -n "$selected_paths" ] || return

    yesno "$(i18n bottles_confirm_title)" "$(i18n bottles_confirm_delete "$selected_names" "$(maintenance_kib_human "$total")")" || return

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            "$BOTTLES_ROOT"/*)
                [ "$path" != "$BOTTLES_ROOT" ] || { failures=$((failures+1)); continue; }
                rm -rf -- "$path" || failures=$((failures+1))
                ;;
            *) failures=$((failures+1)) ;;
        esac
    done <<< "$selected_paths"

    maintenance_bottles_cache_invalidate

    if [ "$failures" -eq 0 ]; then
        msgbox "$(i18n bottles_title)" "$(i18n bottles_delete_done "$(maintenance_kib_human "$total")")"
    else
        msgbox "$(i18n bottles_title)" "$(i18n bottles_delete_partial)"
    fi
}

maintenance_delete_all_bottles() {
    local count total kind runner name path kib orphan failures=0

    count="$(maintenance_bottle_count)"
    total="$(maintenance_bottle_total_kib)"

    [ "$count" -gt 0 ] || {
        msgbox "$(i18n bottles_title)" "$(i18n bottles_none)"
        return
    }

    yesno "$(i18n bottles_warning_title)" "$(i18n bottles_warning)" || return
    yesno "$(i18n bottles_delete_all)" "$(i18n bottles_delete_all_confirm "$count" "$(maintenance_kib_human "$total")")" || return

    while IFS=$'\t' read -r kind runner name path kib orphan; do
        [ -n "$path" ] || continue
        case "$path" in
            "$BOTTLES_ROOT"/*)
                [ "$path" != "$BOTTLES_ROOT" ] || { failures=$((failures+1)); continue; }
                rm -rf -- "$path" || failures=$((failures+1))
                ;;
            *) failures=$((failures+1)) ;;
        esac
    done < <(maintenance_bottle_records)

    maintenance_bottles_cache_invalidate

    if [ "$failures" -eq 0 ]; then
        msgbox "$(i18n bottles_title)" "$(i18n bottles_delete_all_done "$(maintenance_kib_human "$total")")"
    else
        msgbox "$(i18n bottles_title)" "$(i18n bottles_delete_partial)"
    fi
}

maintenance_delete_all_orphans() {
    local count total kind runner name path kib orphan failures=0

    count="$(maintenance_orphan_count)"
    total="$(maintenance_orphan_total_kib)"

    [ "$count" -gt 0 ] || {
        msgbox "$(i18n bottles_orphans)" "$(i18n bottles_no_orphans)"
        return
    }

    yesno "$(i18n bottles_warning_title)" "$(i18n bottles_warning)" || return
    yesno "$(i18n bottles_orphans_delete_all)" "$(i18n bottles_orphans_delete_all_confirm "$count" "$(maintenance_kib_human "$total")")" || return

    while IFS=$'\t' read -r kind runner name path kib orphan; do
        [ "$orphan" = "1" ] || continue
        [ -n "$path" ] || continue
        case "$path" in
            "$BOTTLES_ROOT"/*)
                [ "$path" != "$BOTTLES_ROOT" ] || { failures=$((failures+1)); continue; }
                rm -rf -- "$path" || failures=$((failures+1))
                ;;
            *) failures=$((failures+1)) ;;
        esac
    done < <(maintenance_bottle_records)

    maintenance_bottles_cache_invalidate

    if [ "$failures" -eq 0 ]; then
        msgbox "$(i18n bottles_orphans)" "$(i18n bottles_orphans_delete_all_done "$(maintenance_kib_human "$total")")"
    else
        msgbox "$(i18n bottles_orphans)" "$(i18n bottles_delete_partial)"
    fi
}

maintenance_orphans_menu() {
    while true; do
        local count total choice
        count="$(maintenance_orphan_count)"
        total="$(maintenance_orphan_total_kib)"

        [ "$count" -gt 0 ] || {
            msgbox "$(i18n bottles_orphans)" "$(i18n bottles_no_orphans)"
            return
        }

        choice="$(menu_select "$(i18n bottles_orphans)" \
            "$(i18n bottles_orphans_intro "$count" "$(maintenance_kib_human "$total")")" \
            "1" "$(i18n bottles_orphans_select)" \
            "2" "$(i18n bottles_orphans_delete_all)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) maintenance_delete_selected_bottles orphans ;;
            2) maintenance_delete_all_orphans ;;
            0|"") return ;;
        esac
    done
}

maintenance_bottles_menu() {
    maintenance_bottles_cache_invalidate
    maintenance_bottles_cache_build || {
        msgbox "$(i18n bottles_title)" "$(i18n bottles_scan_failed)"
        return
    }

    while true; do
        local count total choice
        count="$(maintenance_bottle_count)"
        total="$(maintenance_bottle_total_kib)"

        choice="$(menu_select "$(i18n bottles_title)" \
            "$(i18n bottles_intro "$count" "$(maintenance_kib_human "$total")")" \
            "1" "$(i18n bottles_overview_action)" \
            "2" "$(i18n bottles_delete_selected)" \
            "3" "$(i18n bottles_orphans)" \
            "4" "$(i18n bottles_delete_all)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) maintenance_bottles_overview ;;
            2) maintenance_delete_selected_bottles all ;;
            3) maintenance_orphans_menu ;;
            4) maintenance_delete_all_bottles ;;
            0|"") return ;;
        esac
    done
}

maintenance_path_kib() {
    local path="$1"
    if [ -d "$path" ]; then
        maintenance_dir_kib "$path"
    elif [ -f "$path" ]; then
        du -k -- "$path" 2>/dev/null | awk '{print $1+0}'
    else
        printf '0'
    fi
}

maintenance_logs_kib() {
    maintenance_path_kib "$WT_LOG_DIR"
}

maintenance_cache_kib() {
    local total=0 x
    for x in "$WT_HOME/cache" "$WT_HOME/dxvk/cache"; do
        total=$((total + $(maintenance_path_kib "$x")))
    done
    printf '%s' "$total"
}

maintenance_tmp_kib() {
    local total=0 path kib
    shopt -s nullglob
    for path in /tmp/wt-*; do
        [ -e "$path" ] || continue
        kib="$(maintenance_path_kib "$path")"
        total=$((total + kib))
    done
    shopt -u nullglob
    printf '%s' "$total"
}

maintenance_clean_logs() {
    local before current=""
    before="$(maintenance_logs_kib)"

    mkdir -p "$WT_LOG_DIR"
    [ -n "${WT_SESSION_LOG:-}" ] && current="$(readlink -f "$WT_SESSION_LOG" 2>/dev/null || printf '%s' "$WT_SESSION_LOG")"

    while IFS= read -r file; do
        [ -n "$file" ] || continue
        if [ -n "$current" ] && [ "$(readlink -f "$file" 2>/dev/null || printf '%s' "$file")" = "$current" ]; then
            continue
        fi
        rm -f -- "$file" 2>/dev/null || true
    done < <(find "$WT_LOG_DIR" -maxdepth 1 -type f -name '*.log' -print 2>/dev/null)

    if [ -n "${WT_SESSION_LOG:-}" ] && [ -e "$WT_SESSION_LOG" ]; then
        ln -sfn "$(basename "$WT_SESSION_LOG")" "$WT_LOG_DIR/latest.log" 2>/dev/null || true
    else
        rm -f "$WT_LOG_DIR/latest.log" 2>/dev/null || true
    fi

    msgbox "$(i18n cleanup_title)" "$(i18n cleanup_logs_done "$(maintenance_kib_human "$before")")"
}

maintenance_clean_cache_tmp() {
    local cache tmp total path
    cache="$(maintenance_cache_kib)"
    tmp="$(maintenance_tmp_kib)"
    total=$((cache + tmp))

    rm -rf -- "$WT_HOME/cache" "$WT_HOME/dxvk/cache" 2>/dev/null || true
    mkdir -p "$WT_HOME/dxvk/cache"

    shopt -s nullglob
    for path in /tmp/wt-*; do
        rm -rf -- "$path" 2>/dev/null || true
    done
    shopt -u nullglob

    maintenance_bottles_cache_invalidate

    msgbox "$(i18n cleanup_title)" "$(i18n cleanup_temp_done "$(maintenance_kib_human "$total")")"
}

maintenance_cleanup_menu() {
    while true; do
        local logs cache tmp choice
        logs="$(maintenance_logs_kib)"
        cache="$(maintenance_cache_kib)"
        tmp="$(maintenance_tmp_kib)"

        choice="$(menu_select "$(i18n cleanup_title)" \
            "$(i18n cleanup_intro "$(maintenance_kib_human "$logs")" "$(maintenance_kib_human "$cache")" "$(maintenance_kib_human "$tmp")")" \
            "1" "$(i18n cleanup_logs)" \
            "2" "$(i18n cleanup_temp)" \
            "3" "$(i18n cleanup_all)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1)
                yesno "$(i18n cleanup_title)" "$(i18n cleanup_logs_confirm)" && maintenance_clean_logs
                ;;
            2)
                yesno "$(i18n cleanup_title)" "$(i18n cleanup_temp_confirm)" && maintenance_clean_cache_tmp
                ;;
            3)
                yesno "$(i18n cleanup_title)" "$(i18n cleanup_all_confirm)" || continue
                maintenance_clean_logs
                maintenance_clean_cache_tmp
                ;;
            0|"") return ;;
        esac
    done
}

maintenance_show_report() {
    local title="$1" file="$2"

    if have_dialog; then
        wt_clear_tty
        dialog --clear --no-shadow --title "$title" --textbox "$file" 28 110
        local rc=$?
        wt_clear_tty
        return $rc
    fi

    clear
    printf '==== %s ====\n\n' "$title"
    cat "$file"
    printf '\n'
    read -r -p "$(i18n press_enter)" _
}

maintenance_find_runner_binary() {
    local root="$1" name="$2" path

    for path in \
        "$root/bin/$name" \
        "$root/files/bin/$name" \
        "$root/usr/bin/$name"; do
        [ -x "$path" ] && { printf '%s' "$path"; return 0; }
    done

    find "$root" -maxdepth 5 \( -type f -o -type l \) -name "$name" -executable -print -quit 2>/dev/null
}

maintenance_verify_runners() {
    local report runner name wine wineserver broken ok=0 bad=0 total=0
    report="$(mktemp /tmp/wt-runner-check.XXXXXX)" || return

    {
        printf '%s\n' "$(i18n runner_check_header "$BATOCERA_CUSTOM_WINE")"
        printf '\n'
    } > "$report"

    if [ ! -d "$BATOCERA_CUSTOM_WINE" ]; then
        printf '%s\n' "$(i18n runner_check_none)" >> "$report"
        maintenance_show_report "$(i18n runner_check_title)" "$report"
        rm -f "$report"
        return
    fi

    while IFS= read -r runner; do
        [ -d "$runner" ] || continue
        name="$(basename "$runner")"
        total=$((total+1))

        wine="$(maintenance_find_runner_binary "$runner" wine)"
        wineserver="$(maintenance_find_runner_binary "$runner" wineserver)"
        broken="$(find "$runner" -xtype l -print 2>/dev/null | wc -l)"

        if [ -n "$wine" ] && [ -n "$wineserver" ] && [ "$broken" -eq 0 ]; then
            printf '[OK] %s\n' "$name" >> "$report"
            ok=$((ok+1))
        else
            printf '[%s] %s\n' "$(i18n runner_check_problem)" "$name" >> "$report"
            bad=$((bad+1))
        fi
    done < <(find "$BATOCERA_CUSTOM_WINE" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -f)

    if [ "$total" -eq 0 ]; then
        printf '%s\n' "$(i18n runner_check_none)" >> "$report"
    else
        printf '\n%s\n' "$(i18n runner_check_summary "$total" "$ok" "$bad")" >> "$report"
    fi

    maintenance_show_report "$(i18n runner_check_title)" "$report"
    rm -f "$report"
}

maintenance_verify_dxvk() {
    local report bundle name arch dll issues bundle_total=0 bundle_ok=0 bundle_bad=0
    local global_state active_target invalid_games=0 invalid_bundles=0 game_bundle game_path
    local required_dlls="d3d9.dll d3d10core.dll d3d11.dll dxgi.dll d3d12.dll d3d12core.dll"

    report="$(mktemp /tmp/wt-dxvk-check.XXXXXX)" || return

    {
        printf '%s\n\n' "$(i18n dxvk_check_header "$DXVK_BUNDLE_DIR")"

        if [ -s "$DXVK_GLOBAL_FILE" ]; then
            global_state="$(head -n1 "$DXVK_GLOBAL_FILE" | tr -d '\r\n')"
        else
            global_state="$(i18n dxvk_check_no_global_state)"
        fi
        printf '%s : %s\n' "$(i18n dxvk_check_global_state)" "$global_state"

        if [ -L "$BATOCERA_DXVK_PATH" ]; then
            active_target="$(readlink -f "$BATOCERA_DXVK_PATH" 2>/dev/null || true)"
            if [ -n "$active_target" ]; then
                printf '%s : %s\n' "$(i18n dxvk_check_active_link)" "$active_target"
            else
                printf '%s : %s\n' "$(i18n dxvk_check_active_link)" "$(i18n dxvk_check_broken)"
            fi
        elif [ -e "$BATOCERA_DXVK_PATH" ]; then
            printf '%s : %s\n' "$(i18n dxvk_check_active_link)" "$(i18n dxvk_external_custom)"
        else
            printf '%s : %s\n' "$(i18n dxvk_check_active_link)" "$(i18n dxvk_batocera_default)"
        fi
        printf '\n'
    } > "$report"

    if [ -d "$DXVK_BUNDLE_DIR" ]; then
        while IFS= read -r bundle; do
            [ -d "$bundle" ] || continue
            name="$(basename "$bundle")"
            bundle_total=$((bundle_total+1))
            issues=""

            [ -s "$bundle/bundle.conf" ] || issues+="bundle.conf "
            for arch in x64 x32; do
                [ -d "$bundle/$arch" ] || { issues+="$arch/ "; continue; }
                for dll in $required_dlls; do
                    [ -s "$bundle/$arch/$dll" ] || issues+="$arch/$dll "
                done
            done

            if [ -z "$issues" ]; then
                printf '[OK] %s\n' "$name" >> "$report"
                bundle_ok=$((bundle_ok+1))
            else
                printf '[%s] %s\n' "$(i18n dxvk_check_problem)" "$name" >> "$report"
                printf '  %s : %s\n' "$(i18n dxvk_check_missing)" "$issues" >> "$report"
                bundle_bad=$((bundle_bad+1))
            fi
        done < <(find "$DXVK_BUNDLE_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -f)
    fi

    if [ "$bundle_total" -eq 0 ]; then
        printf '%s\n' "$(i18n dxvk_check_none)" >> "$report"
    fi

    printf '\n%s\n' "$(i18n dxvk_check_assignments)" >> "$report"
    if [ -s "$DXVK_GAME_FILE" ]; then
        while IFS=$'\t' read -r game_bundle game_path; do
            [ -n "$game_bundle" ] && [ -n "$game_path" ] || continue
            if [ ! -d "$DXVK_BUNDLE_DIR/$game_bundle" ]; then
                printf '[%s] %s -> %s (%s)\n' "$(i18n dxvk_check_problem)" "$(basename "$game_path")" "$game_bundle" "$(i18n dxvk_check_bundle_missing)" >> "$report"
                invalid_bundles=$((invalid_bundles+1))
            elif [ ! -e "$game_path" ]; then
                printf '[%s] %s -> %s (%s)\n' "$(i18n dxvk_check_problem)" "$(basename "$game_path")" "$game_bundle" "$(i18n dxvk_check_game_missing)" >> "$report"
                invalid_games=$((invalid_games+1))
            else
                printf '[OK] %s -> %s\n' "$(basename "$game_path")" "$game_bundle" >> "$report"
            fi
        done < "$DXVK_GAME_FILE"
    else
        printf '%s\n' "$(i18n dxvk_check_no_assignments)" >> "$report"
    fi

    printf '\n%s\n' "$(i18n dxvk_check_summary "$bundle_total" "$bundle_ok" "$bundle_bad" "$invalid_bundles" "$invalid_games")" >> "$report"

    maintenance_show_report "$(i18n dxvk_check_title)" "$report"
    rm -f "$report"
}

maintenance_list_wine_dirs() {
    [ -d "$WINDOWS_ROMS_DIR" ] || return 0
    find "$WINDOWS_ROMS_DIR" -mindepth 1 -maxdepth 1 -type d -iname '*.wine' -print 2>/dev/null | sort -f
}

maintenance_list_wsquashfs() {
    [ -d "$WINDOWS_ROMS_DIR" ] || return 0
    find "$WINDOWS_ROMS_DIR" -mindepth 1 -maxdepth 1 -type f -iname '*.wsquashfs' -print 2>/dev/null | sort -f
}

maintenance_squash_wine() {
    local source="$1" dest tmp rc=0
    [ -d "$source" ] || return 1

    dest="${source%.wine}.wsquashfs"
    [ ! -e "$dest" ] || return 2

    tmp="$dest.tmp-$$"
    rm -f -- "$tmp" 2>/dev/null || true

    if ! mksquashfs "$source" "$tmp" -comp zstd -no-progress >/dev/null 2>&1; then
        rm -f -- "$tmp" 2>/dev/null || true
        return 1
    fi

    if ! unsquashfs -s "$tmp" >/dev/null 2>&1; then
        rm -f -- "$tmp" 2>/dev/null || true
        return 1
    fi

    mv -f -- "$tmp" "$dest" || rc=1
    return "$rc"
}

maintenance_unsquash_wine() {
    local source="$1" dest tmp rc=0
    [ -f "$source" ] || return 1

    dest="${source%.wsquashfs}.wine"
    [ ! -e "$dest" ] || return 2

    tmp="$dest.tmp-$$"
    rm -rf -- "$tmp" 2>/dev/null || true

    if ! unsquashfs -d "$tmp" "$source" >/dev/null 2>&1; then
        rm -rf -- "$tmp" 2>/dev/null || true
        return 1
    fi

    [ -d "$tmp" ] || {
        rm -rf -- "$tmp" 2>/dev/null || true
        return 1
    }

    mv -- "$tmp" "$dest" || rc=1
    return "$rc"
}

maintenance_select_and_squash() {
    local -a items=()
    local rows="" path selected id idx=1 ok=0 failed=0 skipped=0 rc

    command -v mksquashfs >/dev/null 2>&1 && command -v unsquashfs >/dev/null 2>&1 || {
        msgbox "$(i18n squash_title)" "$(i18n squash_tools_missing)"
        return
    }

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        items+=("$idx" "$(basename "$path")" "off")
        rows+="$path"$'\n'
        idx=$((idx+1))
    done < <(maintenance_list_wine_dirs)

    [ "${#items[@]}" -gt 0 ] || {
        msgbox "$(i18n squash_title)" "$(i18n squash_no_wine)"
        return
    }

    selected="$(checklist_select "$(i18n squash_wine)" "$(i18n squash_select_wine)" "${items[@]}")" || return
    [ -n "$selected" ] || return

    yesno "$(i18n squash_title)" "$(i18n squash_confirm)" || return

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        path="$(sed -n "${id}p" <<< "$rows")"
        [ -n "$path" ] || continue

        maintenance_squash_wine "$path"
        rc=$?
        case "$rc" in
            0) ok=$((ok+1)) ;;
            2) skipped=$((skipped+1)) ;;
            *) failed=$((failed+1)) ;;
        esac
    done <<< "$selected"

    msgbox "$(i18n squash_title)" "$(i18n squash_result "$ok" "$skipped" "$failed")"
}

maintenance_select_and_unsquash() {
    local -a items=()
    local rows="" path selected id idx=1 ok=0 failed=0 skipped=0 rc

    command -v unsquashfs >/dev/null 2>&1 || {
        msgbox "$(i18n squash_title)" "$(i18n squash_tools_missing)"
        return
    }

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        items+=("$idx" "$(basename "$path")" "off")
        rows+="$path"$'\n'
        idx=$((idx+1))
    done < <(maintenance_list_wsquashfs)

    [ "${#items[@]}" -gt 0 ] || {
        msgbox "$(i18n squash_title)" "$(i18n squash_no_wsquashfs)"
        return
    }

    selected="$(checklist_select "$(i18n unsquash_wine)" "$(i18n squash_select_wsquashfs)" "${items[@]}")" || return
    [ -n "$selected" ] || return

    yesno "$(i18n squash_title)" "$(i18n unsquash_confirm)" || return

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        path="$(sed -n "${id}p" <<< "$rows")"
        [ -n "$path" ] || continue

        maintenance_unsquash_wine "$path"
        rc=$?
        case "$rc" in
            0) ok=$((ok+1)) ;;
            2) skipped=$((skipped+1)) ;;
            *) failed=$((failed+1)) ;;
        esac
    done <<< "$selected"

    msgbox "$(i18n squash_title)" "$(i18n unsquash_result "$ok" "$skipped" "$failed")"
}

maintenance_squash_menu() {
    while true; do
        local choice
        choice="$(menu_select "$(i18n squash_title)" "$(i18n squash_intro)" \
            "1" "$(i18n squash_wine)" \
            "2" "$(i18n unsquash_wine)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) maintenance_select_and_squash ;;
            2) maintenance_select_and_unsquash ;;
            0|"") return ;;
        esac
    done
}

maintenance_summary() {
    local wine_count umu_state bottle_count bottle_kib log_kib
    wine_count="$(find /userdata/system/wine/custom -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    umu_state="$(umu_toolbox_status)"

    if [ -s "$BOTTLES_CACHE" ]; then
        bottle_count="$(maintenance_bottle_count)"
        bottle_kib="$(maintenance_bottle_total_kib)"
    else
        bottle_count="$(maintenance_bottle_count)"
        bottle_kib="$(maintenance_bottle_total_kib)"
    fi

    log_kib="$(maintenance_logs_kib)"

    msgbox "$(i18n maintenance_summary_title)" \
        "$(i18n maintenance_summary_body "$(batocera_version)" "$wine_count" "$umu_state" "$bottle_count" "$(maintenance_kib_human "$bottle_kib")" "$(maintenance_kib_human "$log_kib")")"
}

maintenance_menu() {
    while true; do
        local choice
        choice="$(menu_select "$(i18n maintenance_title)" "$(i18n maintenance_intro)" \
            "1" "$(i18n maintenance_summary_title)" \
            "2" "$(i18n bottles_title)" \
            "3" "$(i18n runner_check_title)" \
            "4" "$(i18n dxvk_check_title)" \
            "5" "$(i18n squash_title)" \
            "6" "$(i18n cleanup_title)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) maintenance_summary ;;
            2) maintenance_bottles_menu ;;
            3) maintenance_verify_runners ;;
            4) maintenance_verify_dxvk ;;
            5) maintenance_squash_menu ;;
            6) maintenance_cleanup_menu ;;
            0|"") return ;;
        esac
    done
}
