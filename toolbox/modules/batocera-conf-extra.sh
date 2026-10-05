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

batocera_conf_organize() {
    local backup result rc

    [ -r "$BATOCERA_CONF" ] || {
        msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_unreadable "$BATOCERA_CONF")"
        return
    }
    [ -d "/userdata/roms" ] || {
        msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_systems_missing)"
        return
    }

    yesno_default_no "$(i18n batocera_conf_organize)" "$(i18n batocera_conf_organize_confirm_all)" || return

    backup="$(batocera_conf_backup)" || {
        msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_backup_failed)"
        return
    }

    result="$(python3 - "$BATOCERA_CONF" "/userdata/roms" <<'PY'
from pathlib import Path
import os
import re
import shutil
import sys
import tempfile

conf = Path(sys.argv[1])
roms = Path(sys.argv[2])
marker = "# ------------ User-generated Configurations ----------- #"
protected_heading = "## Enable DXVK for Wine and FPS HUD."
generated_header_re = re.compile(r'^# ===== \[ [A-Z0-9_.+ -]+ \] =====\s*batocera_conf_menu() {
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
)
per_game_re = re.compile(r'^\s*([A-Za-z0-9_-]+)\["([^"]+)"\](?:-renderer)?\.')
global_re = re.compile(r'^\s*([A-Za-z0-9_-]+)(?:-renderer)?\.')

with conf.open("r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
    lines = fh.readlines()

marker_indexes = [i for i, raw in enumerate(lines) if raw.rstrip("\r\n") == marker]
if not marker_indexes:
    print("ERROR:MARKER")
    raise SystemExit(20)
marker_index = marker_indexes[0]

newline = "\r\n" if any(raw.endswith("\r\n") for raw in lines) else "\n"

# Detect actual Batocera systems from /userdata/roms. This keeps unrelated
# configuration namespaces (global.*, audio.*, network.*, etc.) out of scope.
systems = set()
try:
    for p in roms.iterdir():
        if p.is_dir():
            systems.add(p.name.casefold())
except OSError:
    raise SystemExit(21)
systems.add("windows")

def classify(raw):
    line = raw.rstrip("\r\n")
    if not line or line.lstrip().startswith("#"):
        return None

    m = per_game_re.match(line)
    if m:
        prefix = m.group(1).casefold()
        base = "windows" if prefix == "windows-renderer" else prefix
        if base in systems:
            return ("game", base, m.group(2))
        return None

    m = global_re.match(line)
    if m:
        prefix = m.group(1).casefold()
        base = "windows" if prefix == "windows-renderer" else prefix
        if base in systems:
            return ("global", base, None)
    return None

# Protect the stock DXVK/FPS HUD block exactly where Batocera ships it.
protected = set()
for i in range(0, marker_index):
    if lines[i].rstrip("\r\n") != protected_heading:
        continue
    protected.add(i)
    j = i + 1
    while j < marker_index:
        text = lines[j].rstrip("\r\n")
        if text == "":
            protected.add(j)
            break
        protected.add(j)
        j += 1

collected = {}
def add_entry(kind, system, game, raw):
    bucket = collected.setdefault(system, {"global": [], "games": {}, "game_order": []})
    if kind == "global":
        bucket["global"].append(raw)
    else:
        if game not in bucket["games"]:
            bucket["games"][game] = []
            bucket["game_order"].append(game)
        bucket["games"][game].append(raw)

# Before the user-generated marker: move only recognized active system/game
# options, except for the protected stock DXVK block.
prefix = []
for i, raw in enumerate(lines[:marker_index]):
    if i in protected:
        prefix.append(raw)
        continue
    cls = classify(raw)
    if cls:
        add_entry(*cls, raw)
    else:
        prefix.append(raw)

# Keep the marker itself unchanged.
marker_line = lines[marker_index]

# In the user-generated section, retain unrelated content exactly, while
# extracting recognized system/game settings for normalized grouping.
user_other = []
for raw in lines[marker_index + 1:]:
    text = raw.rstrip("\r\n")
    if generated_header_re.match(text):
        continue
    cls = classify(raw)
    if cls:
        add_entry(*cls, raw)
    else:
        user_other.append(raw)

# Trim only trailing empty lines from the unrelated user section so repeated
# organization remains stable and does not accumulate whitespace.
while user_other and user_other[-1].strip() == "":
    user_other.pop()

out = list(prefix)
out.append(marker_line)
if user_other:
    if not marker_line.endswith(("\n", "\r\n")):
        out[-1] += newline
    out.extend(user_other)
    out.append(newline)

system_names = sorted(collected, key=str.casefold)
for pos, system in enumerate(system_names):
    if out and out[-1].strip() != "":
        out.append(newline)

    title = system.upper()
    out.append(f"# ===== [ {title} ] ====={newline}")
    out.append(newline)

    bucket = collected[system]
    out.extend(bucket["global"])

    game_names = sorted(bucket["games"], key=str.casefold)
    if bucket["global"] and game_names:
        out.append(newline)

    for game in game_names:
        out.extend(bucket["games"][game])

    if pos != len(system_names) - 1:
        out.append(newline)

fd, tmp_name = tempfile.mkstemp(prefix=".batocera.conf.wt-", dir=str(conf.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as out_fh:
        out_fh.writelines(out)
        out_fh.flush()
        os.fsync(out_fh.fileno())
    shutil.copystat(conf, tmp_name)
    os.replace(tmp_name, conf)
finally:
    if os.path.exists(tmp_name):
        os.unlink(tmp_name)

print(f"OK:{len(system_names)}:{sum(len(v[\'global\']) + sum(len(x) for x in v[\'games\'].values()) for v in collected.values())}")
PY
)"
    rc=$?

    if [ "$rc" -eq 20 ] || [ "$result" = "ERROR:MARKER" ]; then
        msgbox "$(i18n batocera_conf_organize)" "$(i18n batocera_conf_marker_missing "$backup")"
        return
    fi
    if [ "$rc" -ne 0 ]; then
        msgbox "$(i18n batocera_conf_organize)" "$(i18n batocera_conf_modify_failed "$backup")"
        return
    fi

    local systems_count lines_count
    systems_count="$(printf '%s' "$result" | awk -F: '{print $2}')"
    lines_count="$(printf '%s' "$result" | awk -F: '{print $3}')"
    msgbox "$(i18n batocera_conf_organize)" \
        "$(i18n batocera_conf_organize_done_all "${systems_count:-0}" "${lines_count:-0}" "$backup")"
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
