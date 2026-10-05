#!/bin/bash

ROOT="/userdata/system/ultimate-wine-toolbox"
CONFIG_DIR="$ROOT/config"
GLOBAL_FILE="$CONFIG_DIR/mangohud-global"
OVERRIDE_FILE="$CONFIG_DIR/mangohud-games.tsv"

event="${1:-}"
system="${2:-}"
rom="${5:-}"

[ "$event" = "gameStart" ] || exit 0
[ "$system" = "windows" ] || exit 0
[ -n "$rom" ] || exit 0

global_state="0"
[ -s "$GLOBAL_FILE" ] && global_state="$(head -n1 "$GLOBAL_FILE" | tr -d '\r\n[:space:]')"
case "$global_state" in 1|on|ON|true|TRUE) global_state=1 ;; *) global_state=0 ;; esac

override=""
if [ -s "$OVERRIDE_FILE" ]; then
    override="$(awk -F '\t' -v p="$rom" '$2==p {v=$1} END{print v}' "$OVERRIDE_FILE")"
fi

case "$override" in
    on) desired=1 ;;
    off) desired=0 ;;
    *) desired="$global_state" ;;
esac

rewrite_autorun() {
    local file="$1" state="$2"
    [ -f "$file" ] || return 1

    python3 - "$file" "$state" <<'PY'
import re, sys
from pathlib import Path

path=Path(sys.argv[1])
enabled=sys.argv[2] == "1"
try:
    text=path.read_text(encoding="utf-8", errors="replace")
except Exception:
    raise SystemExit(1)

lines=text.replace("\r\n","\n").replace("\r","\n").split("\n")
out=[]
found=False

for line in lines:
    if line.startswith("ENV=") and not found:
        payload=line[4:]
        payload=re.sub(r'(^|\s)MANGOHUD=[^\s]+', ' ', payload)
        payload=re.sub(r'\s+', ' ', payload).strip()
        if enabled:
            payload=(payload + " " if payload else "") + "MANGOHUD=1"
        if payload:
            out.append("ENV="+payload)
        found=True
    else:
        out.append(line)

if enabled and not found:
    insert_at=0
    for i,line in enumerate(out):
        if line.startswith(("DIR=","CMD=","LANG=","SAVEDIR=","SAVEFILES=")):
            insert_at=i
            break
    out.insert(insert_at, "ENV=MANGOHUD=1")

while out and out[-1] == "":
    out.pop()
path.write_text("\n".join(out)+"\n", encoding="utf-8")
PY
}

get_runner() {
    local romname="$1" runner
    runner="$(batocera-settings-get "windows[\"$romname\"].wine-runner" "windows.wine-runner" "global.wine-runner" 2>/dev/null || true)"
    if [ -z "$runner" ]; then
        runner="$(batocera-settings-get "windows[\"$romname\"].core" "windows.core" "global.core" 2>/dev/null || true)"
    fi
    case "$runner" in
        lutris) runner="wine-tkg" ;;
        proton) runner="wine-proton" ;;
        "") runner="wine-tkg" ;;
    esac
    printf '%s' "$runner"
}

case "${rom,,}" in
    *.pc|*.wine)
        [ -d "$rom" ] || exit 0
        rewrite_autorun "$rom/autorun.cmd" "$desired" || true
        ;;
    *.wsquashfs)
        [ -f "$rom" ] || exit 0
        romname="$(basename "$rom")"
        runner="$(get_runner "$romname")"
        upper="/userdata/system/wine-bottles/windows/$runner/$romname.wine"
        autorun="$upper/autorun.cmd"
        if [ ! -f "$autorun" ]; then
            tmp="$(mktemp /tmp/wt-mangohud-autorun.XXXXXX)" || exit 0
            if unsquashfs -cat "$rom" autorun.cmd > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
                mkdir -p "$upper"
                cp -f "$tmp" "$autorun"
            fi
            rm -f "$tmp"
        fi
        [ -f "$autorun" ] && rewrite_autorun "$autorun" "$desired" || true
        ;;
    *.wtgz)
        romname="$(basename "$rom")"
        runner="$(get_runner "$romname")"
        prefix="/userdata/system/wine-bottles/windows/$runner/$romname.wine"
        [ -f "$prefix/autorun.cmd" ] && rewrite_autorun "$prefix/autorun.cmd" "$desired" || true
        ;;
esac

exit 0
