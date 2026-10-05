#!/bin/bash

LOG_DIR="/userdata/system/logs/ultimate-wine-toolbox"
BOOT_LOG="$LOG_DIR/port-launch.log"
LAUNCHER="/userdata/system/ultimate-wine-toolbox/toolbox/launch-in-terminal.sh"

mkdir -p "$LOG_DIR"
export DISPLAY="${DISPLAY:-:0}"

# Batocera 41/42 may launch Ports with a non-UTF-8 locale. Reuse Batocera's
# configured system language so dialog/xterm render accents and other UTF-8
# characters correctly.
BATOCERA_LANG="$(batocera-settings-get system.language 2>/dev/null | tr -d '\r\n[:space:]' || true)"
BATOCERA_LANG="${BATOCERA_LANG%%.*}"
if [ -n "$BATOCERA_LANG" ]; then
    export LANG="$BATOCERA_LANG.UTF-8"
    export LC_ALL="$BATOCERA_LANG.UTF-8"
elif [[ "${LC_ALL:-${LANG:-}}" != *UTF-8* && "${LC_ALL:-${LANG:-}}" != *utf8* ]]; then
    export LANG="C.UTF-8"
    export LC_ALL="C.UTF-8"
fi

{
    echo
    echo "===== $(date '+%Y-%m-%d %H:%M:%S %z') ====="
    echo "port_launcher=$0"
    echo "uid=$(id -u 2>/dev/null || true)"
    echo "DISPLAY=$DISPLAY"
    echo "TERM=${TERM:-<unset>}"
    echo "LANG=${LANG:-<unset>}"
    echo "LC_ALL=${LC_ALL:-<unset>}"
    echo "xterm=$(command -v xterm 2>/dev/null || true)"
    echo "launcher=$LAUNCHER"
} >>"$BOOT_LOG" 2>&1

if [ ! -x /usr/bin/xterm ]; then
    echo "ERROR: /usr/bin/xterm missing or not executable." >>"$BOOT_LOG"
    exit 1
fi

if [ ! -s "$LAUNCHER" ]; then
    echo "ERROR: terminal launcher missing: $LAUNCHER" >>"$BOOT_LOG"
    exit 1
fi

/usr/bin/xterm     -u8     -fa "DejaVu Sans Mono"     -fs 10     -title "Ultimate Wine Toolbox"     -geometry 120x36     -e /bin/bash "$LAUNCHER"     >>"$BOOT_LOG" 2>&1

rc=$?
echo "xterm_exit_code=$rc" >>"$BOOT_LOG"
exit "$rc"
