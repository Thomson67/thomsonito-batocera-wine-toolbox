#!/bin/bash
set -euo pipefail

cd /tmp 2>/dev/null || true

REPO="Thomson67/ultimate-wine-toolbox"
BRANCH="test"
ARCHIVE_URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"

TMP="$(mktemp -d /tmp/ultimate-wine-toolbox.XXXXXX)"
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

for cmd in curl tar python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    say "ERREUR : $cmd est introuvable." "ERROR: $cmd is missing."
    exit 1
  }
done

say "Téléchargement de la branche test..." "Downloading test branch..."
curl -fL --retry 3 --connect-timeout 15 "$ARCHIVE_URL" -o "$TMP/test.tar.gz"

tar -tzf "$TMP/test.tar.gz" >/dev/null || {
  say "ERREUR : l'archive GitHub téléchargée est invalide." "ERROR: downloaded GitHub archive is invalid."
  exit 1
}

tar -xzf "$TMP/test.tar.gz" -C "$TMP"
ROOT="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name '*-test' -print -quit)"

[ -n "$ROOT" ] && [ -s "$ROOT/package-install.sh" ] || {
  say "ERREUR : package-install.sh est absent de la branche test." "ERROR: package-install.sh is missing from the test branch."
  exit 1
}

for f in "$ROOT/package-install.sh" "$ROOT/uninstall.sh" "$ROOT/toolbox/ultimate-wine-toolbox.sh" "$ROOT/toolbox/lib/common.sh" "$ROOT/toolbox/modules/starter-pack.sh" "$ROOT/toolbox/modules/batocera-conf.sh" "$ROOT/toolbox/modules/batocera-conf-extra.sh" "$ROOT/toolbox/modules/batocera-conf-transfer.sh"; do
  /bin/bash -n "$f" || {
    say "ERREUR : erreur de syntaxe dans $f" "ERROR: syntax error in $f"
    exit 1
  }
done

[ -s "$ROOT/toolbox/helpers/batocera_conf_transfer.py" ] || {
  say "ERREUR : helper batocera_conf_transfer.py absent." "ERROR: batocera_conf_transfer.py helper is missing."
  exit 1
}

python3 -m py_compile "$ROOT/toolbox/helpers/batocera_conf_transfer.py" || {
  say "ERREUR : erreur de syntaxe dans batocera_conf_transfer.py" "ERROR: syntax error in batocera_conf_transfer.py"
  exit 1
}

chmod +x "$ROOT/package-install.sh"
say "Installation de la version test..." "Installing test version..."
exec "$ROOT/package-install.sh"
