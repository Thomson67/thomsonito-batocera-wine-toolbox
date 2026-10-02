#!/bin/bash
set -euo pipefail

DEST="/userdata/system/thomsonito-wine-toolbox"
PORT="/userdata/roms/ports/Thomsonito Batocera Wine Toolbox.sh"
KEYS="$PORT.keys"

case "${LC_ALL:-${LANG:-}}" in fr*|fr_*) L=fr ;; *) L=en ;; esac
say() {
    if [ "$L" = "fr" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}

[ "$(id -u)" -eq 0 ] || {
    say "ERREUR : lancez ce désinstalleur en root." "ERROR: run this uninstaller as root."
    exit 1
}

rm -rf "$DEST"
rm -f "$PORT" "$KEYS"

say "Toolbox supprimée. Les runners Wine/UMU installés ont été conservés." \
    "Toolbox removed. Installed Wine/UMU runners were left untouched."
