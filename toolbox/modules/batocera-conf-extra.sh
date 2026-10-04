#!/bin/bash

batocera_conf_clean_all_orphans() {
    local scan rc summary orphan_games orphan_lines kind game count selected_file backup removed

    scan="$(batocera_conf_scan)"
    rc=$?
    case "$rc" in
        0) ;;
        10)
            msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_unreadable "$BATOCERA_CONF")"
            return
            ;;
        11)
            msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_roms_missing "$WINDOWS_ROMS_DIR")"
            return
            ;;
        *)
            msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_scan_failed)"
            return
            ;;
    esac

    summary="$(printf '%s\n' "$scan" | awk -F '\t' '$1=="SUMMARY"{print; exit}')"
    IFS=$'\t' read -r _ _ _ _ orphan_games orphan_lines <<< "$summary"

    [ "$orphan_games" -gt 0 ] || {
        msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_no_orphans)"
        return
    }

    yesno_default_no "$(i18n batocera_conf_clean_all)" \
        "$(i18n batocera_conf_clean_all_confirm "$orphan_games" "$orphan_lines")" || return

    selected_file="$(mktemp /tmp/wt-batocera-conf-all-orphans.XXXXXX)" || return
    : > "$selected_file"
    while IFS=$'\t' read -r kind game count; do
        [ "$kind" = "ORPHAN" ] || continue
        [ -n "$game" ] && printf '%s\n' "$game" >> "$selected_file"
    done <<< "$scan"

    backup="$(batocera_conf_backup)" || {
        rm -f "$selected_file"
        msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_backup_failed)"
        return
    }

    removed="$(python3 - "$BATOCERA_CONF" "$selected_file" <<'PY'
from pathlib import Path
import os
import re
import shutil
import sys
import tempfile

conf = Path(sys.argv[1])
selected_file = Path(sys.argv[2])
selected = {line for line in selected_file.read_text(encoding="utf-8", errors="surrogateescape").splitlines() if line}
game_re = re.compile(r'^\s*windows\["([^"]+)"\]')

with conf.open("r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
    lines = fh.readlines()

kept = []
removed = 0
for raw in lines:
    match = game_re.match(raw.rstrip("\r\n"))
    if match and match.group(1) in selected:
        removed += 1
    else:
        kept.append(raw)

fd, tmp_name = tempfile.mkstemp(prefix=".batocera.conf.wt-", dir=str(conf.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as out:
        out.writelines(kept)
        out.flush()
        os.fsync(out.fileno())
    shutil.copystat(conf, tmp_name)
    os.replace(tmp_name, conf)
finally:
    if os.path.exists(tmp_name):
        os.unlink(tmp_name)

print(removed)
PY
)"
    rc=$?
    rm -f "$selected_file"

    if [ "$rc" -eq 0 ]; then
        msgbox "$(i18n batocera_conf_clean_all)" "$(i18n batocera_conf_clean_all_done "$removed" "$backup")"
    else
        msgbox "$(i18n batocera_conf_clean_all)" "$(i18n batocera_conf_modify_failed "$backup")"
    fi
}

batocera_conf_restore() {
    local -a items=()
    local rows="" path idx=1 count=0 choice selected backup_current tmp rc=0

    [ -d "$BATOCERA_CONF_BACKUP_DIR" ] || {
        msgbox "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_restore_none "$BATOCERA_CONF_BACKUP_DIR")"
        return
    }

    while IFS= read -r path; do
        [ -f "$path" ] || continue
        case "$(basename "$path")" in
            batocera.conf-*.bak) ;;
            *) continue ;;
        esac
        items+=("$idx" "$(basename "$path")")
        rows+="$path"$'\n'
        idx=$((idx+1))
        count=$((count+1))
    done < <(find "$BATOCERA_CONF_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type f -name 'batocera.conf-*.bak' -print 2>/dev/null | sort -r)

    [ "$count" -gt 0 ] || {
        msgbox "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_restore_none "$BATOCERA_CONF_BACKUP_DIR")"
        return
    }

    choice="$(menu_select "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_restore_prompt "$count")" "${items[@]}")" || return
    [ -n "$choice" ] || return

    selected="$(sed -n "${choice}p" <<< "$rows")"
    [ -f "$selected" ] || {
        msgbox "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_restore_invalid)"
        return
    }

    case "$selected" in
        "$BATOCERA_CONF_BACKUP_DIR"/batocera.conf-*.bak) ;;
        *)
            msgbox "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_restore_invalid)"
            return
            ;;
    esac

    yesno_default_no "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_restore_confirm "$(basename "$selected")")" || return

    backup_current="$(batocera_conf_backup)" || {
        msgbox "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_backup_failed)"
        return
    }

    tmp="$(mktemp /userdata/system/.batocera.conf.restore.XXXXXX)" || rc=1
    if [ "$rc" -eq 0 ]; then
        cp -p -- "$selected" "$tmp" || rc=1
    fi
    if [ "$rc" -eq 0 ]; then
        mv -f -- "$tmp" "$BATOCERA_CONF" || rc=1
    fi
    [ -n "${tmp:-}" ] && [ -e "$tmp" ] && rm -f -- "$tmp"

    if [ "$rc" -eq 0 ]; then
        msgbox "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_restore_done "$(basename "$selected")" "$backup_current")"
    else
        msgbox "$(i18n batocera_conf_restore)" "$(i18n batocera_conf_restore_failed "$backup_current")"
    fi
}

# Override the submenu defined by batocera-conf.sh with the extended one.
batocera_conf_menu() {
    while true; do
        local choice
        choice="$(menu_select "$(i18n batocera_conf_title)" "$(i18n batocera_conf_intro)" \
            "1" "$(i18n batocera_conf_analyze)" \
            "2" "$(i18n batocera_conf_clean)" \
            "3" "$(i18n batocera_conf_clean_all)" \
            "4" "$(i18n batocera_conf_organize)" \
            "5" "$(i18n batocera_conf_restore)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) batocera_conf_analyze ;;
            2) batocera_conf_clean_orphans ;;
            3) batocera_conf_clean_all_orphans ;;
            4) batocera_conf_organize ;;
            5) batocera_conf_restore ;;
            0|"") return ;;
        esac
    done
}
