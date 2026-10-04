#!/bin/bash
set -u

ROOT="/userdata/system/thomsonito-wine-toolbox/toolbox"
MAIN="$ROOT/thomsonito-wine-toolbox.sh"
LOG_DIR="/userdata/system/logs/thomsonito-wine-toolbox"
mkdir -p "$LOG_DIR"

# Keep only the 20 most recent Toolbox session logs.
ls -1t "$LOG_DIR"/toolbox-*.log 2>/dev/null | tail -n +20 | while IFS= read -r oldlog; do
    [ -n "$oldlog" ] && rm -f -- "$oldlog"
done

STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG="$LOG_DIR/toolbox-$STAMP.log"
ln -sfn "$(basename "$LOG")" "$LOG_DIR/latest.log" 2>/dev/null || true

# IMPORTANT: do not pipe stdout/stderr through tee here.
# dialog must keep a real TTY on stderr or its screen handling becomes unstable.
export WT_SESSION_LOG="$LOG"

{
    echo "===== Thomsonito Batocera Wine Toolbox ====="
    echo "date=$(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "user=$(id -un 2>/dev/null || true) uid=$(id -u 2>/dev/null || true)"
    echo "pwd=$(pwd)"
    echo "DISPLAY=${DISPLAY:-<unset>}"
    echo "TERM=${TERM:-<unset>}"
    echo "main=$MAIN"
} >>"$LOG" 2>&1

if [ ! -s "$MAIN" ]; then
    echo "ERROR: main script missing: $MAIN" | tee -a "$LOG" >&2
    rc=70
elif ! /bin/bash -n "$MAIN" >>"$LOG" 2>&1; then
    echo "ERROR: main script syntax check failed. See $LOG" >&2
    rc=71
else
    /bin/bash "$MAIN"
    rc=$?
fi

{
    echo "toolbox_exit_code=$rc"
    echo "log=$LOG"
} >>"$LOG" 2>&1

if [ "$rc" -ne 0 ]; then
    echo
    echo "The Toolbox exited with an error (code $rc)."
    echo "Log: $LOG"
    echo "Press Enter to close this terminal."
    read -r _
fi

exit "$rc"
