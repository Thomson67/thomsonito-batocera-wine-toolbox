#!/bin/bash
ROOT="/userdata/system/ultimate-wine-toolbox"
[ "${2:-}" = windows ] || exit 0
case "${1:-}" in gameStart|gameStop) ;; *) exit 0 ;; esac
[ -n "${5:-}" ] || exit 0
LOG_DIR="/userdata/system/logs/ultimate-wine-toolbox"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/reshade-game-event.log"
if [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -- "$LOG" "$LOG_DIR/reshade-game-event-$(date +%Y%m%d-%H%M%S)-$$.log"
    ls -1t "$LOG_DIR"/reshade-game-event-*.log 2>/dev/null | tail -n +20 | while IFS= read -r old; do rm -f -- "$old"; done
fi
args=()
# 40-42 have no per-runner .wine upper-directory layout.
if ! grep -Fq 'WINE_BOTTLE_DIR}/${WINE_VERSION}/${ROMGAMENAME}.wine' /usr/bin/batocera-wine 2>/dev/null; then
    args+=(--legacy)
fi
printf '[%s] %s %s\n' "$(date '+%F %T')" "$1" "$5" >> "$LOG"
if ! python3 "$ROOT/toolbox/helpers/reshade_manager.py" --home "$ROOT" "${args[@]}" "$1" "$5" >> "$LOG" 2>&1; then
    printf '[%s] ReShade preparation failed; consult this log.\n' "$(date '+%F %T')" >> "$LOG"
fi
exit 0
