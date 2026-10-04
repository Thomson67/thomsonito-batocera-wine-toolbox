#!/bin/bash

BOTTLES_ROOT="/userdata/system/wine-bottles/windows"
WINDOWS_ROMS_DIR="/userdata/roms/windows"
WT_LOG_DIR="/userdata/system/logs/thomsonito-wine-toolbox"

maintenance_dir_kib() {
    local path="$1"
    du -sk -- "$path" 2>/dev/null | awk '{print $1+0}'
}

maintenance_kib_human() {
    local kib="${1:-0}"
    human_bytes "$((kib * 1024))"
}

maintenance_bottle_records() {
    [ -d "$BOTTLES_ROOT" ] || return 0

    python3 - "$BOTTLES_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
if not root.is_dir():
    raise SystemExit

def is_runner_container(p: Path) -> bool:
    try:
        if (p / "default-prefix").is_dir() or (p / "default-settings").exists():
            return True
        return any(c.is_dir() and c.name.endswith(".wine") for c in p.iterdir())
    except OSError:
        return False

# Batocera 43+ : <runner>/<rom>.wine
for runner in sorted((p for p in root.iterdir() if p.is_dir()), key=lambda p: p.name.lower()):
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
        print("v43\t{}\t{}\t{}".format(runner.name, bottle.name, bottle))

# Legacy : direct children of wine-bottles/windows.
for bottle in sorted((p for p in root.iterdir() if p.is_dir()), key=lambda p: p.name.lower()):
    if bottle.name in {"default-prefix", "default-settings"}:
        continue
    if is_runner_container(bottle):
        continue
    print("legacy\t-\t{}\t{}".format(bottle.name, bottle))
PY
}

maintenance_bottle_count() {
    maintenance_bottle_records | awk 'END{print NR+0}'
}

maintenance_bottle_total_kib() {
    local kind runner name path total=0 kib
    while IFS=$'\t' read -r kind runner name path; do
        [ -n "$path" ] || continue
        kib="$(maintenance_dir_kib "$path")"
        total=$((total + kib))
    done < <(maintenance_bottle_records)
    printf '%s' "$total"
}

maintenance_game_exists_for_bottle() {
    local name="$1" candidate rom base stem

    [ -d "$WINDOWS_ROMS_DIR" ] || return 1

    candidate="$name"
    candidate="${candidate%.wine}"

    [ -e "$WINDOWS_ROMS_DIR/$candidate" ] && return 0

    for rom in "$WINDOWS_ROMS_DIR"/*; do
        [ -e "$rom" ] || continue
        base="$(basename "$rom")"
        stem="$base"
        case "${stem,,}" in
            *.wsquashfs) stem="${stem%.*}" ;;
            *.wtgz)      stem="${stem%.*}" ;;
            *.wine)      stem="${stem%.*}" ;;
            *.pc)        stem="${stem%.*}" ;;
        esac

        [ "$candidate" = "$base" ] && return 0
        [ "$candidate" = "$stem" ] && return 0
        [ "$name" = "$base" ] && return 0
    done

    return 1
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
    local rows="" kind runner name path kib label idx=1 count=0
    local selected="" id selected_paths="" selected_names="" total=0 failures=0

    while IFS=$'\t' read -r kind runner name path; do
        [ -n "$path" ] || continue

        if [ "$mode" = "orphans" ] && maintenance_game_exists_for_bottle "$name"; then
            continue
        fi

        kib="$(maintenance_dir_kib "$path")"
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

    if [ "$failures" -eq 0 ]; then
        msgbox "$(i18n bottles_title)" "$(i18n bottles_delete_done "$(maintenance_kib_human "$total")")"
    else
        msgbox "$(i18n bottles_title)" "$(i18n bottles_delete_partial)"
    fi
}

maintenance_delete_all_bottles() {
    local count total kind runner name path failures=0

    count="$(maintenance_bottle_count)"
    total="$(maintenance_bottle_total_kib)"

    [ "$count" -gt 0 ] || {
        msgbox "$(i18n bottles_title)" "$(i18n bottles_none)"
        return
    }

    yesno "$(i18n bottles_warning_title)" "$(i18n bottles_warning)" || return
    yesno "$(i18n bottles_delete_all)" "$(i18n bottles_delete_all_confirm "$count" "$(maintenance_kib_human "$total")")" || return

    while IFS=$'\t' read -r kind runner name path; do
        [ -n "$path" ] || continue
        case "$path" in
            "$BOTTLES_ROOT"/*)
                [ "$path" != "$BOTTLES_ROOT" ] || { failures=$((failures+1)); continue; }
                rm -rf -- "$path" || failures=$((failures+1))
                ;;
            *) failures=$((failures+1)) ;;
        esac
    done < <(maintenance_bottle_records)

    if [ "$failures" -eq 0 ]; then
        msgbox "$(i18n bottles_title)" "$(i18n bottles_delete_all_done "$(maintenance_kib_human "$total")")"
    else
        msgbox "$(i18n bottles_title)" "$(i18n bottles_delete_partial)"
    fi
}

maintenance_bottles_menu() {
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
            3) maintenance_delete_selected_bottles orphans ;;
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

maintenance_summary() {
    local wine_count umu_state bottle_count bottle_kib log_kib
    wine_count="$(find /userdata/system/wine/custom -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    umu_state="$(umu_toolbox_status)"
    bottle_count="$(maintenance_bottle_count)"
    bottle_kib="$(maintenance_bottle_total_kib)"
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
            "3" "$(i18n cleanup_title)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) maintenance_summary ;;
            2) maintenance_bottles_menu ;;
            3) maintenance_cleanup_menu ;;
            0|"") return ;;
        esac
    done
}
