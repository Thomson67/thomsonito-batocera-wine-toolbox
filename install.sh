#!/bin/bash
set -euo pipefail

REPO="Thomson67/thomsonito-batocera-wine-toolbox"
BRANCH="test"
PACKAGE="thomsonito-batocera-wine-toolbox-v0.1.0-dev5.zip"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH/packages/$PACKAGE"

TMP="$(mktemp -d /tmp/thomsonito-wine-toolbox.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

case "${LC_ALL:-${LANG:-}}" in
  fr*|fr_*) LANG_UI=fr ;;
  *) LANG_UI=en ;;
esac

say() {
  if [ "$LANG_UI" = "fr" ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$2"
  fi
}

[ "$(id -u)" -eq 0 ] || {
  say "ERREUR : lancez cette commande en root." "ERROR: run this command as root."
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  say "ERREUR : curl est introuvable." "ERROR: curl is missing."
  exit 1
}

command -v unzip >/dev/null 2>&1 || {
  say "ERREUR : unzip est introuvable." "ERROR: unzip is missing."
  exit 1
}

say "Téléchargement de la branche test..." "Downloading test branch package..."
curl -fL "$RAW" -o "$TMP/$PACKAGE"

unzip -q "$TMP/$PACKAGE" -d "$TMP"

ROOT="$TMP/thomsonito-batocera-wine-toolbox-v0.1.0-dev5"
[ -x "$ROOT/install.sh" ] || chmod +x "$ROOT/install.sh"

say "Installation de la version test..." "Installing test version..."
exec "$ROOT/install.sh"
