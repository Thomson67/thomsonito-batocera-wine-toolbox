#!/bin/bash
set -euo pipefail

cd /tmp 2>/dev/null || true

REPO="Thomson67/ultimate-wine-toolbox"
CHANNEL="${WT_INSTALL_CHANNEL:-stable}"
TMP="$(mktemp -d /tmp/ultimate-wine-toolbox.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

case "${LC_ALL:-${LANG:-}}" in
  fr*|fr_*) LANG_UI=fr ;;
  *) LANG_UI=en ;;
esac

say() {
  if [ "$LANG_UI" = "fr" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}

fail() {
  say "ERREUR : $1" "ERROR: $2"
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "lancez cette commande en root." "run this command as root."

install_tree() {
  local root="$1"

  [ -n "$root" ] && [ -s "$root/package-install.sh" ] ||     fail "package-install.sh est absent du package." "package-install.sh is missing from the package."

  while IFS= read -r script; do
    /bin/bash -n "$script" ||       fail "erreur de syntaxe dans $script" "syntax error in $script"
  done < <(find "$root" -type f -name '*.sh' -print)

  [ -s "$root/toolbox/helpers/batocera_conf_transfer.py" ] ||     fail "helper batocera_conf_transfer.py absent." "batocera_conf_transfer.py helper is missing."

  python3 -m py_compile "$root/toolbox/helpers/batocera_conf_transfer.py" ||     fail "erreur de syntaxe dans batocera_conf_transfer.py" "syntax error in batocera_conf_transfer.py"

  chmod +x "$root/package-install.sh"
  exec "$root/package-install.sh"
}

install_test_branch() {
  local archive="$TMP/test.tar.gz" root

  for cmd in curl tar python3; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd est introuvable." "$cmd is missing."
  done

  say "Téléchargement de la branche test..." "Downloading test branch..."
  curl -fL --retry 3 --connect-timeout 15     "https://github.com/$REPO/archive/refs/heads/test.tar.gz"     -o "$archive" || fail "téléchargement de la branche test impossible." "unable to download the test branch."

  tar -tzf "$archive" >/dev/null || fail "archive test invalide." "invalid test archive."
  tar -xzf "$archive" -C "$TMP"
  root="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name '*-test' -print -quit)"
  install_tree "$root"
}

install_stable_release() {
  local latest_url tag asset checksum base root package_version

  for cmd in curl unzip sha256sum python3; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd est introuvable." "$cmd is missing."
  done

  say "Recherche de la dernière release stable..." "Looking for the latest stable release..."
  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}'     "https://github.com/$REPO/releases/latest")" ||     fail "impossible de déterminer la dernière release." "unable to determine the latest release."

  tag="$(basename "$latest_url")"
  case "$tag" in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) fail "tag de release inattendu : $tag" "unexpected release tag: $tag" ;;
  esac

  asset="Ultimate-Wine-Toolbox-$tag.zip"
  checksum="${asset}.sha256"
  base="https://github.com/$REPO/releases/download/$tag"

  say "Version détectée : $tag" "Detected version: $tag"
  say "Téléchargement du package officiel..." "Downloading official package..."

  if ! curl -fL --retry 3 --connect-timeout 15 -o "$TMP/$asset" "$base/$asset"; then
    if [ "$tag" = "v0.1.0" ]; then
      say "La v0.1.0 ne contient pas encore d'asset dédié : utilisation exceptionnelle de main."           "v0.1.0 has no dedicated asset yet: using main as a one-time fallback."
      CHANNEL=test
      # v0.1.0 transitional fallback: main contains the published stable source.
      curl -fL --retry 3 --connect-timeout 15         "https://github.com/$REPO/archive/refs/heads/main.tar.gz"         -o "$TMP/main.tar.gz" || fail "fallback main impossible." "main fallback failed."
      tar -xzf "$TMP/main.tar.gz" -C "$TMP"
      root="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name '*-main' -print -quit)"
      install_tree "$root"
    fi
    fail "téléchargement du package $tag impossible." "unable to download package $tag."
  fi

  curl -fL --retry 3 --connect-timeout 15 -o "$TMP/$checksum" "$base/$checksum" ||     fail "checksum SHA-256 absent pour $tag." "SHA-256 checksum is missing for $tag."

  (cd "$TMP" && sha256sum -c "$checksum" >/dev/null 2>&1) ||     fail "vérification SHA-256 échouée." "SHA-256 verification failed."

  unzip -q "$TMP/$asset" -d "$TMP/extracted" ||     fail "extraction du package impossible." "unable to extract the package."

  root="$TMP/extracted/Ultimate-Wine-Toolbox-$tag"
  [ -s "$root/VERSION" ] || fail "VERSION absente du package." "VERSION is missing from the package."

  package_version="$(tr -d '\r\n[:space:]' < "$root/VERSION")"
  [ "v$package_version" = "$tag" ] ||     fail "la version du package ne correspond pas à la release." "package version does not match the release."

  install_tree "$root"
}

case "$CHANNEL" in
  test) install_test_branch ;;
  stable|"") install_stable_release ;;
  *) fail "canal d'installation inconnu : $CHANNEL" "unknown installation channel: $CHANNEL" ;;
esac
