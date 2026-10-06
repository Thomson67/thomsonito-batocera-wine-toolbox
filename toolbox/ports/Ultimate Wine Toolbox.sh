#!/bin/bash

LOG_DIR="/userdata/system/logs/ultimate-wine-toolbox"
BOOT_LOG="$LOG_DIR/port-launch.log"
LAUNCHER="/userdata/system/ultimate-wine-toolbox/toolbox/launch-in-terminal.sh"

mkdir -p "$LOG_DIR"
export DISPLAY="${DISPLAY:-:0}"

# xterm decides its character encoding when the terminal process starts.
# EmulationStation/Ports may launch us without the UTF-8 locale later selected
# by launch-in-terminal.sh, so initialize a known UTF-8 locale before xterm.
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

/usr/bin/xterm \
    +lc \
    -u8 \
    -fa "DejaVu Sans Mono" \
    -fs 10 \
    -title "Ultimate Wine Toolbox" \
    -geometry 120x36 \
    -e /bin/bash "$LAUNCHER" \
    >>"$BOOT_LOG" 2>&1

rc=$?
echo "xterm_exit_code=$rc" >>"$BOOT_LOG"

STATE_DIR="/userdata/system/ultimate-wine-toolbox/state"
RESTART_REQUEST="$STATE_DIR/restart-es.request"
LAUNCH_REQUEST="$STATE_DIR/launch-game.request"

wait_for_es_api() {
    local attempt=0
    while [ "$attempt" -lt 40 ]; do
        attempt=$((attempt + 1))
        if command -v curl >/dev/null 2>&1; then
            if curl -fsS --max-time 1 http://127.0.0.1:1234/ >/dev/null 2>&1; then
                echo "es_api_ready_after_attempt=$attempt" >>"$BOOT_LOG"
                return 0
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q -T 1 -O /dev/null http://127.0.0.1:1234/ >/dev/null 2>&1; then
                echo "es_api_ready_after_attempt=$attempt" >>"$BOOT_LOG"
                return 0
            fi
        else
            echo "ERROR: curl/wget unavailable; cannot probe ES API." >>"$BOOT_LOG"
            return 1
        fi
        sleep 0.25
    done

    echo "ERROR: ES API not ready after timeout." >>"$BOOT_LOG"
    return 1
}

launch_game_via_es() {
    local rom="$1"
    [ -n "$rom" ] || return 1

    echo "es_launch_rom=$rom" >>"$BOOT_LOG"

    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 5 -X POST --data-binary "$rom"             http://127.0.0.1:1234/launch >>"$BOOT_LOG" 2>&1
        return $?
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q -T 5 --post-data="$rom" -O -             http://127.0.0.1:1234/launch >>"$BOOT_LOG" 2>&1
        return $?
    fi

    return 1
}

launch_rom=""
if [ -f "$LAUNCH_REQUEST" ]; then
    IFS= read -r launch_rom < "$LAUNCH_REQUEST" || true
    rm -f -- "$LAUNCH_REQUEST"
    echo "es_launch_requested=1" >>"$BOOT_LOG"
fi

if [ -f "$RESTART_REQUEST" ]; then
    rm -f -- "$RESTART_REQUEST"
    {
        echo "es_restart_requested=1"
        echo "es_restart_time=$(date '+%Y-%m-%d %H:%M:%S %z')"
    } >>"$BOOT_LOG"

    if command -v batocera-es-swissknife >/dev/null 2>&1; then
        batocera-es-swissknife --restart >>"$BOOT_LOG" 2>&1
        restart_rc=$?
        echo "es_restart_exit_code=$restart_rc" >>"$BOOT_LOG"

        if [ "$restart_rc" -eq 0 ] && [ -n "$launch_rom" ]; then
            if wait_for_es_api; then
                launch_game_via_es "$launch_rom"
                echo "es_launch_exit_code=$?" >>"$BOOT_LOG"
            else
                echo "ERROR: automatic game launch skipped because ES API is unavailable." >>"$BOOT_LOG"
            fi
        fi
    else
        echo "ERROR: batocera-es-swissknife not found; ES restart skipped." >>"$BOOT_LOG"
    fi
elif [ -n "$launch_rom" ]; then
    if wait_for_es_api; then
        launch_game_via_es "$launch_rom"
        echo "es_launch_exit_code=$?" >>"$BOOT_LOG"
    fi
fi

exit "$rc"
