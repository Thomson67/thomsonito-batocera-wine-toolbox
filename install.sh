#!/bin/bash
set -euo pipefail

cd /tmp 2>/dev/null || true

REPO="Thomson67/thomsonito-batocera-wine-toolbox"
BRANCH="test"
BASE_PACKAGE="thomsonito-batocera-wine-toolbox-v0.1.0-dev5.zip"
BASE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH/packages/$BASE_PACKAGE"
BASE_SIZE="21230"
BASE_SHA256="5d2c75677118caa1a7b1debb04964e17f28487ebb116c3c932266c39a6ab6213"

TMP="$(mktemp -d /tmp/thomsonito-wine-toolbox.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

case "${LC_ALL:-${LANG:-}}" in
  fr*|fr_*) LANG_UI=fr ;;
  *) LANG_UI=en ;;
esac

say() {
  if [ "$LANG_UI" = "fr" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
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

say "Téléchargement de la base validée..." "Downloading validated base..."
curl -fL "$BASE_URL" -o "$TMP/$BASE_PACKAGE"

size="$(stat -c '%s' "$TMP/$BASE_PACKAGE")"
[ "$size" = "$BASE_SIZE" ] || {
  say "ERREUR : package de base incomplet ($size octets reçus, $BASE_SIZE attendus)."       "ERROR: incomplete base package ($size bytes received, $BASE_SIZE expected)."
  exit 1
}

actual_sha="$(sha256sum "$TMP/$BASE_PACKAGE" | awk '{print $1}')"
[ "$actual_sha" = "$BASE_SHA256" ] || {
  say "ERREUR : SHA-256 invalide pour le package de base."       "ERROR: invalid SHA-256 for the base package."
  exit 1
}

unzip -tq "$TMP/$BASE_PACKAGE" >/dev/null || {
  say "ERREUR : le package de base n'est pas un ZIP valide."       "ERROR: base package is not a valid ZIP."
  exit 1
}

unzip -q "$TMP/$BASE_PACKAGE" -d "$TMP"
ROOT="$TMP/thomsonito-batocera-wine-toolbox-v0.1.0-dev5"

say "Application des correctifs de la branche test..." "Applying test branch patches..."

fetch_patch() {
  local rel="$1"
  mkdir -p "$(dirname "$ROOT/$rel")"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/overlays/$rel" -o "$ROOT/$rel"
}

fetch_patch "VERSION"
fetch_patch "toolbox/lib/common.sh"
fetch_patch "toolbox/lang/fr.sh"
fetch_patch "toolbox/lang/en.sh"
fetch_patch "toolbox/modules/starter-pack.sh"

for f in   "$ROOT/toolbox/lib/common.sh"   "$ROOT/toolbox/lang/fr.sh"   "$ROOT/toolbox/lang/en.sh"   "$ROOT/toolbox/modules/starter-pack.sh"
do
  /bin/bash -n "$f" || {
    say "ERREUR : un correctif test contient une erreur de syntaxe : $f"         "ERROR: a test patch contains a syntax error: $f"
    exit 1
  }
done

chmod +x "$ROOT/install.sh"
say "Installation de la version test..." "Installing test version..."
exec "$ROOT/install.sh"
