#!/bin/bash

LOG_DIR="/userdata/system/logs/ultimate-wine-toolbox"
BOOT_LOG="$LOG_DIR/port-launch.log"
LAUNCHER="/userdata/system/ultimate-wine-toolbox/toolbox/launch-in-terminal.sh"

mkdir -p "$LOG_DIR"
export DISPLAY="${DISPLAY:-:0}"

# Batocera 41/42 may launch Ports with a non-UTF-8 locale.
select_utf8_locale() {
    local syslang candidate available
    syslang="$(batocera-settings-get system.language 2>/dev/null | tr -d '\r\n[:space:]' || true)"
    syslang="${syslang%%.*}"

    available="$(locale -a 2>/dev/null || true)"
    for candidate in "$syslang.UTF-8" "$syslang.utf8" "C.UTF-8" "C.utf8" "en_US.UTF-8" "en_US.utf8"; do
        [ -n "$candidate" ] || continue
        if printf '%s\n' "$available" | grep -Fxqi "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    # Last fallback: keep UTF-8 semantics requested by xterm even on very
    # minimal builds where locale -a is incomplete.
    printf '%s' "C.UTF-8"
}

WT_UTF8_LOCALE="$(select_utf8_locale)"
export LANG="$WT_UTF8_LOCALE"
export LC_ALL="$WT_UTF8_LOCALE"
export LANGUAGE="$WT_UTF8_LOCALE"

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

/usr/bin/xterm     -u8 1     -fa "DejaVu Sans Mono"     -fs 10     -title "Ultimate Wine Toolbox"     -geometry 120x36     -e /bin/bash "$LAUNCHER"     >>"$BOOT_LOG" 2>&1

rc=$?
echo "xterm_exit_code=$rc" >>"$BOOT_LOG"
exit "$rc"
