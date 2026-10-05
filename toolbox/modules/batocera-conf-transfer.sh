#!/bin/bash

BATOCERA_WINDOWS_EXPORT_DIR="$WT_HOME/exports/windows-config"

batocera_conf_export_windows() {
    local stamp output result rc global_count game_count game_lines

    [ -r "$BATOCERA_CONF" ] || {
        msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_unreadable "$BATOCERA_CONF")"
        return
    }

    mkdir -p "$BATOCERA_WINDOWS_EXPORT_DIR" || {
        msgbox "$(i18n batocera_conf_export_title)" "$(i18n batocera_conf_export_dir_failed "$BATOCERA_WINDOWS_EXPORT_DIR")"
        return
    }

    stamp="$(date '+%Y%m%d-%H%M%S')"
    output="$BATOCERA_WINDOWS_EXPORT_DIR/windows-config-$stamp.conf"

    result="$(python3 - "$BATOCERA_CONF" "$output" "$(batocera_version)" <<'PY'
from pathlib import Path
import re
import sys

conf = Path(sys.argv[1])
output = Path(sys.argv[2])
batocera = sys.argv[3]

game_re = re.compile(r'^\s*(windows\["([^"]+)"\](?:-renderer)?\..*)$')
global_re = re.compile(r'^\s*((?:windows|windows-renderer)\..*)$')
protected_key_re = re.compile(r'^\s*windows\.dxvk(?:_hud)?=')

globals_ = []
games = {}

with conf.open("r", encoding="utf-8", errors="surrogateescape") as fh:
    for raw in fh:
        line = raw.rstrip("\r\n")
        if not line or line.lstrip().startswith("#"):
            continue
        if protected_key_re.match(line):
            continue

        match = game_re.match(line)
        if match:
            game = match.group(2)
            games.setdefault(game, []).append(line)
            continue

        match = global_re.match(line)
        if match:
            globals_.append(match.group(1))

lines = [
    "# Thomsonito Batocera Wine Toolbox - Windows configuration export",
    "# THOMSONITO_WINDOWS_CONFIG_EXPORT=1",
    f"# SOURCE_BATOCERA={batocera}",
    "# Protected stock settings windows.dxvk/windows.dxvk_hud are intentionally excluded.",
    "",
]
lines.extend(globals_)
if globals_ and games:
    lines.append("")

for game in sorted(games, key=str.casefold):
    lines.extend(games[game])

output.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"{len(globals_)}\t{len(games)}\t{sum(len(v) for v in games.values())}")
PY
)"
    rc=$?

    if [ "$rc" -ne 0 ] || [ ! -s "$output" ]; then
        rm -f -- "$output"
        msgbox "$(i18n batocera_conf_export_title)" "$(i18n batocera_conf_export_failed)"
        return
    fi

    IFS=$'\t' read -r global_count game_count game_lines <<< "$result"
    msgbox "$(i18n batocera_conf_export_title)" \
        "$(i18n batocera_conf_export_done "$global_count" "$game_count" "$game_lines" "$output")"
}

batocera_conf_import_windows_file() {
    local source="$1" backup result rc global_count game_count game_lines

    [ -f "$source" ] || {
        msgbox "$(i18n batocera_conf_import_title)" "$(i18n batocera_conf_import_invalid)"
        return
    }

    [ -r "$BATOCERA_CONF" ] || {
        msgbox "$(i18n batocera_conf_title)" "$(i18n batocera_conf_unreadable "$BATOCERA_CONF")"
        return
    }

    result="$(python3 - "$source" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
allowed = re.compile(r'^\s*(?:windows(?:-renderer)?\.|windows\["[^"]+"\](?:-renderer)?\.)')
protected = re.compile(r'^\s*windows\.dxvk(?:_hud)?=')
game_re = re.compile(r'^\s*windows\["([^"]+)"\](?:-renderer)?\.')

lines = source.read_text(encoding="utf-8", errors="strict").splitlines()
if "# THOMSONITO_WINDOWS_CONFIG_EXPORT=1" not in lines[:8]:
    raise SystemExit(10)

global_count = 0
games = set()
game_lines = 0

for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if protected.match(line):
        raise SystemExit(11)
    if not allowed.match(line):
        raise SystemExit(12)

    match = game_re.match(line)
    if match:
        games.add(match.group(1))
        game_lines += 1
    else:
        global_count += 1

print(f"{global_count}\t{len(games)}\t{game_lines}")
PY
)"
    rc=$?

    case "$rc" in
        0) ;;
        10)
            msgbox "$(i18n batocera_conf_import_title)" "$(i18n batocera_conf_import_bad_format)"
            return
            ;;
        11|12)
            msgbox "$(i18n batocera_conf_import_title)" "$(i18n batocera_conf_import_unsafe)"
            return
            ;;
        *)
            msgbox "$(i18n batocera_conf_import_title)" "$(i18n batocera_conf_import_invalid)"
            return
            ;;
    esac

    IFS=$'\t' read -r global_count game_count game_lines <<< "$result"

    yesno_default_no "$(i18n batocera_conf_import_title)" \
        "$(i18n batocera_conf_import_confirm "$(basename "$source")" "$global_count" "$game_count" "$game_lines")" || return

    backup="$(batocera_conf_backup)" || {
        msgbox "$(i18n batocera_conf_import_title)" "$(i18n batocera_conf_backup_failed)"
        return
    }

    result="$(python3 - "$BATOCERA_CONF" "$source" <<'PY'
from pathlib import Path
import os
import re
import shutil
import sys
import tempfile

conf = Path(sys.argv[1])
source = Path(sys.argv[2])
marker = "# ------------ User-generated Configurations ----------- #"
protected_heading = "## Enable DXVK for Wine and FPS HUD."
generated_header_re = re.compile(r'^# ===== \[ ([A-Z0-9_.+ -]+) \] =====\s*$')
windows_line_re = re.compile(r'^\s*(?:windows(?:-renderer)?\.|windows\["[^"]+"\](?:-renderer)?\.)')
protected_key_re = re.compile(r'^\s*windows\.dxvk(?:_hud)?=')
game_re = re.compile(r'^\s*windows\["([^"]+)"\](?:-renderer)?\.')

with conf.open("r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
    lines = fh.readlines()

marker_indexes = [i for i, raw in enumerate(lines) if raw.rstrip("\r\n") == marker]
if not marker_indexes:
    raise SystemExit(20)
marker_index = marker_indexes[0]
newline = "\r\n" if any(raw.endswith("\r\n") for raw in lines) else "\n"

protected_indexes = set()
for i in range(marker_index):
    if lines[i].rstrip("\r\n") != protected_heading:
        continue
    pos = i
    while pos < marker_index:
        protected_indexes.add(pos)
        if pos > i and lines[pos].rstrip("\r\n") == "":
            break
        pos += 1
    break

imported = []
for raw in source.read_text(encoding="utf-8", errors="strict").splitlines():
    if not raw or raw.lstrip().startswith("#"):
        continue
    if protected_key_re.match(raw) or not windows_line_re.match(raw):
        raise SystemExit(21)
    imported.append(raw + newline)

before = []
for i, raw in enumerate(lines[:marker_index]):
    text = raw.rstrip("\r\n")
    if i in protected_indexes:
        before.append(raw)
    elif windows_line_re.match(text):
        continue
    else:
        before.append(raw)

after = []
inside_windows_header = False
for raw in lines[marker_index + 1:]:
    text = raw.rstrip("\r\n")
    header = generated_header_re.match(text)
    if header:
        inside_windows_header = header.group(1).casefold() == "windows"
        if inside_windows_header:
            continue
        after.append(raw)
        continue

    if windows_line_re.match(text):
        continue

    if inside_windows_header and not text:
        continue

    inside_windows_header = False
    after.append(raw)

while after and after[-1].strip() == "":
    after.pop()

insert_at = len(after)
for i, raw in enumerate(after):
    match = generated_header_re.match(raw.rstrip("\r\n"))
    if match and match.group(1).casefold() > "windows":
        insert_at = i
        break

globals_ = []
games = {}
for raw in imported:
    match = game_re.match(raw.rstrip("\r\n"))
    if match:
        games.setdefault(match.group(1), []).append(raw)
    else:
        globals_.append(raw)

windows_block = []
if globals_ or games:
    windows_block.append(f"# ===== [ WINDOWS ] ====={newline}")
    windows_block.append(newline)
    windows_block.extend(globals_)
    if globals_ and games:
        windows_block.append(newline)
    for game in sorted(games, key=str.casefold):
        windows_block.extend(games[game])
    if insert_at < len(after):
        windows_block.append(newline)

new_after = after[:insert_at] + windows_block + after[insert_at:]

output = list(before)
output.append(lines[marker_index])
if new_after:
    if output[-1].strip() and new_after[0].strip():
        output.append(newline)
    output.extend(new_after)

fd, tmp_name = tempfile.mkstemp(prefix=".batocera.conf.wt-import-", dir=str(conf.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as out:
        out.writelines(output)
        out.flush()
        os.fsync(out.fileno())
    shutil.copystat(conf, tmp_name)
    os.replace(tmp_name, conf)
finally:
    if os.path.exists(tmp_name):
        os.unlink(tmp_name)

print(len(imported))
PY
)"
    rc=$?

    if [ "$rc" -eq 0 ]; then
        msgbox "$(i18n batocera_conf_import_title)" "$(i18n batocera_conf_import_done "$result" "$backup")"
    else
        msgbox "$(i18n batocera_conf_import_title)" "$(i18n batocera_conf_import_failed "$backup")"
    fi
}

batocera_conf_import_windows() {
    local -a items=()
    local rows="" path idx=1 count=0 choice selected mode manual

    mkdir -p "$BATOCERA_WINDOWS_EXPORT_DIR" || {
        msgbox "$(i18n batocera_conf_import_title)" "$(i18n batocera_conf_export_dir_failed "$BATOCERA_WINDOWS_EXPORT_DIR")"
        return
    }

    mode="$(menu_select "$(i18n batocera_conf_import_title)" \
        "$(i18n batocera_conf_import_source_prompt "$BATOCERA_WINDOWS_EXPORT_DIR")" \
        "1" "$(i18n batocera_conf_import_from_folder)" \
        "2" "$(i18n batocera_conf_import_manual)" \
        "0" "$(i18n back)")" || return

    case "$mode" in
        1)
            while IFS= read -r path; do
                [ -f "$path" ] || continue
                items+=("$idx" "$(basename "$path")")
                rows+="$path"$'\n'
                idx=$((idx+1))
                count=$((count+1))
            done < <(find "$BATOCERA_WINDOWS_EXPORT_DIR" -mindepth 1 -maxdepth 1 \
                -type f -name 'windows-config-*.conf' -print 2>/dev/null | sort -r)

            [ "$count" -gt 0 ] || {
                msgbox "$(i18n batocera_conf_import_title)" \
                    "$(i18n batocera_conf_import_none "$BATOCERA_WINDOWS_EXPORT_DIR")"
                return
            }

            choice="$(menu_select "$(i18n batocera_conf_import_title)" \
                "$(i18n batocera_conf_import_choose "$count")" \
                "${items[@]}")" || return
            [ -n "$choice" ] || return
            selected="$(sed -n "${choice}p" <<< "$rows")"
            ;;
        2)
            manual="$(input_text "$(i18n batocera_conf_import_title)" \
                "$(i18n batocera_conf_import_manual_prompt)" \
                "$BATOCERA_WINDOWS_EXPORT_DIR/")" || return
            selected="$manual"
            ;;
        *)
            return
            ;;
    esac

    batocera_conf_import_windows_file "$selected"
}

batocera_conf_menu() {
    while true; do
        local choice
        choice="$(menu_select "$(i18n batocera_conf_title)" "$(i18n batocera_conf_intro)" \
            "1" "$(i18n batocera_conf_analyze)" \
            "2" "$(i18n batocera_conf_clean)" \
            "3" "$(i18n batocera_conf_clean_all)" \
            "4" "$(i18n batocera_conf_organize)" \
            "5" "$(i18n batocera_conf_export_title)" \
            "6" "$(i18n batocera_conf_import_title)" \
            "7" "$(i18n batocera_conf_restore)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) batocera_conf_analyze ;;
            2) batocera_conf_clean_orphans ;;
            3) batocera_conf_clean_all_orphans ;;
            4) batocera_conf_organize ;;
            5) batocera_conf_export_windows ;;
            6) batocera_conf_import_windows ;;
            7) batocera_conf_restore ;;
            0|"") return ;;
        esac
    done
}
