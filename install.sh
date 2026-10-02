#!/bin/bash
set -euo pipefail

REPO="Thomson67/thomsonito-batocera-wine-toolbox"
BRANCH="test"
PACKAGE="thomsonito-batocera-wine-toolbox-v0.1.0-dev6.zip"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH/packages/$PACKAGE"
EXPECTED_SIZE="22645"
EXPECTED_SHA256="219a8e55b9ee65907b7975fb74af2ea561e9edc2f43ff9ebd61085426f5181af"

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

for cmd in curl unzip sha256sum stat; do
  command -v "$cmd" >/dev/null 2>&1 || {
    say "ERREUR : $cmd est introuvable." "ERROR: $cmd is missing."
    exit 1
  }
done

say "Téléchargement de la branche test..." "Downloading test branch package..."
curl -fL "$RAW" -o "$TMP/$PACKAGE"

size="$(stat -c '%s' "$TMP/$PACKAGE")"
if [ "$size" != "$EXPECTED_SIZE" ]; then
  say "ERREUR : package incomplet ($size octets reçus, $EXPECTED_SIZE attendus)."       "ERROR: incomplete package ($size bytes received, $EXPECTED_SIZE expected)."
  exit 1
fi

actual_sha="$(sha256sum "$TMP/$PACKAGE" | awk '{print $1}')"
if [ "$actual_sha" != "$EXPECTED_SHA256" ]; then
  say "ERREUR : SHA-256 invalide pour le package de test."       "ERROR: invalid SHA-256 for the test package."
  echo "expected=$EXPECTED_SHA256"
  echo "actual=$actual_sha"
  exit 1
fi

if ! unzip -tq "$TMP/$PACKAGE" >/dev/null; then
  say "ERREUR : l'archive téléchargée n'est pas un ZIP valide."       "ERROR: downloaded archive is not a valid ZIP."
  exit 1
fi

unzip -q "$TMP/$PACKAGE" -d "$TMP"

ROOT="$TMP/thomsonito-batocera-wine-toolbox-v0.1.0-dev6"
[ -x "$ROOT/install.sh" ] || chmod +x "$ROOT/install.sh"

say "Installation de la version test..." "Installing test version..."
exec "$ROOT/install.sh"
