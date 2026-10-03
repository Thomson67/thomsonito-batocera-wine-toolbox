#!/bin/bash
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="/userdata/system/thomsonito-wine-toolbox"
PORTS="/userdata/roms/ports"
PORT_NAME="Thomsonito Batocera Wine Toolbox.sh"
PORT="$PORTS/$PORT_NAME"
KEYS="$PORTS/$PORT_NAME.keys"
SCRIPTS="/userdata/system/scripts"
MANGOHUD_HOOK="$SCRIPTS/thomsonito-wine-toolbox-mangohud.sh"

case "${LC_ALL:-${LANG:-}}" in fr*|fr_*) L=fr ;; *) L=en ;; esac

say() {
    if [ "$L" = "fr" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}

[ "$(id -u)" -eq 0 ] || {
    say "ERREUR : lancez cet installateur en root." "ERROR: run this installer as root."
    exit 1
}

mkdir -p "$DEST" "$PORTS" "$SCRIPTS"
rm -rf "$DEST/toolbox"
cp -a "$SRC/toolbox" "$DEST/toolbox"
cp -a "$SRC/VERSION" "$DEST/VERSION"

chmod +x "$DEST/toolbox/thomsonito-wine-toolbox.sh"
chmod +x "$DEST/toolbox/launch-in-terminal.sh"
chmod +x "$DEST/toolbox/modules/"*.sh "$DEST/toolbox/lib/"*.sh "$DEST/toolbox/hooks/"*.sh 2>/dev/null || true

if [ ! -s "$DEST/toolbox/ports/$PORT_NAME" ]; then
    say "ERREUR : lanceur Ports absent du package." "ERROR: Ports launcher missing from package."
    exit 1
fi
cp -f "$DEST/toolbox/ports/$PORT_NAME" "$PORT"
chmod +x "$PORT"

# Native Batocera Pad2Key/evmapy mapping. The filename must match the Port exactly.
if [ ! -s "$DEST/toolbox/ports/$PORT_NAME.keys" ]; then
    say "ERREUR : mapping Pad2Key absent du package." "ERROR: Pad2Key mapping missing from package."
    exit 1
fi
cp -f "$DEST/toolbox/ports/$PORT_NAME.keys" "$KEYS"

if [ -s "$DEST/toolbox/hooks/mangohud-game-event.sh" ]; then
    cp -f "$DEST/toolbox/hooks/mangohud-game-event.sh" "$MANGOHUD_HOOK"
    chmod +x "$MANGOHUD_HOOK"
fi

# Refresh the Ports list when the helper exists; harmless on older Batocera builds.
command -v batocera-es-swissknife >/dev/null 2>&1 && batocera-es-swissknife --update-gamelists >/dev/null 2>&1 || true

echo
say "Thomsonito Batocera Wine Toolbox installée." \
    "Thomsonito Batocera Wine Toolbox installed."
say "Pad2Key natif Batocera installé." \
    "Native Batocera Pad2Key installed."
say "Lancement : Ports -> Thomsonito Batocera Wine Toolbox" \
    "Launch: Ports -> Thomsonito Batocera Wine Toolbox"
