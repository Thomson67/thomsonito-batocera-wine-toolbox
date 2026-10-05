#!/bin/bash
set -u

ROOT="/userdata/system/ultimate-wine-toolbox/toolbox"
MAIN="$ROOT/ultimate-wine-toolbox.sh"
LOG_DIR="/userdata/system/logs/ultimate-wine-toolbox"
mkdir -p "$LOG_DIR"

# Safety net for direct launches: ensure a UTF-8 locale even when Batocera 41/42
# starts the script from an environment using the C locale.
if [[ "${LC_ALL:-${LANG:-}}" != *UTF-8* && "${LC_ALL:-${LANG:-}}" != *utf8* ]]; then
    BATOCERA_LANG="$(batocera-settings-get system.language 2>/dev/null | tr -d '\\r\\n[:space:]' || true)"
    BATOCERA_LANG="${BATOCERA_LANG%%.*}"
    if [ -n "$BATOCERA_LANG" ]; then
        export LANG="$BATOCERA_LANG.UTF-8"
        export LC_ALL="$BATOCERA_LANG.UTF-8"
    else
        export LANG="C.UTF-8"
        export LC_ALL="C.UTF-8"
    fi
fi

# Keep only the 20 most recent Toolbox session logs.
ls -1t "$LOG_DIR"/toolbox-*.log 2>/dev/null | tail -n +21 | while IFS= read -r oldlog; do
    [ -n "$oldlog" ] && rm -f -- "$oldlog"
done

STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG="$LOG_DIR/toolbox-$STAMP.log"
ln -sfn "$(basename "$LOG")" "$LOG_DIR/latest.log" 2>/dev/null || true

# IMPORTANT: do not pipe stdout/stderr through tee here.
# dialog must keep a real TTY on stderr or its screen handling becomes unstable.
export WT_SESSION_LOG="$LOG"

{
    echo "===== Ultimate Wine Toolbox ====="
    echo "date=$(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "user=$(id -un 2>/dev/null || true) uid=$(id -u 2>/dev/null || true)"
    echo "pwd=$(pwd)"
    echo "DISPLAY=${DISPLAY:-<unset>}"
    echo "TERM=${TERM:-<unset>}"
    echo "LANG=${LANG:-<unset>}"
    echo "LC_ALL=${LC_ALL:-<unset>}"
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
