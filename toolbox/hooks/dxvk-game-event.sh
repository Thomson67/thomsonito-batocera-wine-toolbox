#!/bin/bash

ROOT="/userdata/system/thomsonito-wine-toolbox"
CONFIG_DIR="$ROOT/config"
BUNDLE_DIR="$ROOT/dxvk/bundles"
GLOBAL_FILE="$CONFIG_DIR/dxvk-global"
GAME_FILE="$CONFIG_DIR/dxvk-games.tsv"
DXVK_PATH="/userdata/system/wine/dxvk"

event="${1:-}"
system="${2:-}"
rom="${5:-}"

[ "$system" = "windows" ] || exit 0

managed_target() {
    local target
    [ -L "$DXVK_PATH" ] || return 1
    target="$(readlink -f "$DXVK_PATH" 2>/dev/null || true)"
    case "$target" in
        "$BUNDLE_DIR"/*) return 0 ;;
        *) return 1 ;;
    esac
}

apply_state() {
    local state="$1" target

    if [ "$state" = "batocera" ] || [ -z "$state" ]; then
        if managed_target; then
            rm -f "$DXVK_PATH"
        fi
        return 0
    fi

    target="$BUNDLE_DIR/$state"
    [ -d "$target/x64" ] && [ -d "$target/x32" ] || return 0

    if [ -e "$DXVK_PATH" ] && [ ! -L "$DXVK_PATH" ]; then
        return 0
    fi

    if [ -L "$DXVK_PATH" ] && ! managed_target; then
        return 0
    fi

    rm -f "$DXVK_PATH" 2>/dev/null || true
    ln -s "$target" "$DXVK_PATH" 2>/dev/null || true
}

global_state=""
if [ -s "$GLOBAL_FILE" ]; then
    global_state="$(head -n1 "$GLOBAL_FILE" | tr -d '\r\n')"
fi

if [ -z "$global_state" ]; then
    if managed_target; then
        target="$(readlink -f "$DXVK_PATH" 2>/dev/null || true)"
        global_state="$(basename "$target")"
    elif [ ! -e "$DXVK_PATH" ] && [ ! -L "$DXVK_PATH" ]; then
        global_state="batocera"
    else
        exit 0
    fi
fi

case "$event" in
    gameStart)
        [ -n "$rom" ] || exit 0
        override=""
        if [ -s "$GAME_FILE" ]; then
            override="$(awk -F '\t' -v p="$rom" '$2==p {v=$1} END{print v}' "$GAME_FILE")"
        fi

        if [ -n "$override" ] && [ -d "$BUNDLE_DIR/$override" ]; then
            apply_state "$override"
        else
            apply_state "$global_state"
        fi
        ;;
    gameStop)
        apply_state "$global_state"
        ;;
esac

exit 0
