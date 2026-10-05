#!/bin/bash
set -euo pipefail

DEST="/userdata/system/ultimate-wine-toolbox"
PORT="/userdata/roms/ports/Ultimate Wine Toolbox.sh"
KEYS="$PORT.keys"
MANGOHUD_HOOK="/userdata/system/scripts/ultimate-wine-toolbox-mangohud.sh"
DXVK_HOOK="/userdata/system/scripts/ultimate-wine-toolbox-dxvk.sh"
DXVK_PATH="/userdata/system/wine/dxvk"
DXVK_BUNDLES="$DEST/dxvk/bundles"

# Legacy development-name artifacts are removed as well.
OLD_DEST="/userdata/system/thomsonito-wine-toolbox"
OLD_PORT="/userdata/roms/ports/Thomsonito Batocera Wine Toolbox.sh"
OLD_MANGOHUD_HOOK="/userdata/system/scripts/thomsonito-wine-toolbox-mangohud.sh"
OLD_DXVK_HOOK="/userdata/system/scripts/thomsonito-wine-toolbox-dxvk.sh"

case "${LC_ALL:-${LANG:-}}" in fr*|fr_*) L=fr ;; *) L=en ;; esac
say() {
    if [ "$L" = "fr" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}

[ "$(id -u)" -eq 0 ] || {
    say "ERREUR : lancez ce désinstalleur en root." "ERROR: run this uninstaller as root."
    exit 1
}

if [ -L "$DXVK_PATH" ]; then
    target="$(readlink -f "$DXVK_PATH" 2>/dev/null || true)"
    case "$target" in
        "$DXVK_BUNDLES"/*|"$OLD_DEST"/dxvk/bundles/*) rm -f "$DXVK_PATH" ;;
    esac
fi

rm -rf "$DEST" "$OLD_DEST"
rm -f "$PORT" "$KEYS" "$MANGOHUD_HOOK" "$DXVK_HOOK"
rm -f "$OLD_PORT" "$OLD_PORT.keys" "$OLD_MANGOHUD_HOOK" "$OLD_DXVK_HOOK"

say "Ultimate Wine Toolbox supprimée. Les runners Wine/UMU installés ont été conservés." \
    "Ultimate Wine Toolbox removed. Installed Wine/UMU runners were left untouched."
