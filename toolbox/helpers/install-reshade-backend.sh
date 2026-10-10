#!/bin/bash
# ReShadeLinux v1.3.5 (GPL-2.0-or-later), unmodified and checksum-pinned.
set -euo pipefail
ROOT="${WT_HOME:-/userdata/system/ultimate-wine-toolbox}"
BACKEND="$ROOT/reshade/backend"
COMMIT=f20e2dee1f5f584cbe5246866554e14406c473e9
HASH=a4fd90726f540ff21a4fda8886c9abd3f0a87ba75f2c373352112aac92b333ef
mkdir -p "$ROOT/reshade"
exec 9> "$ROOT/reshade/backend.lock"
flock 9
if [ -f "$BACKEND/commit" ] && [ "$(cat "$BACKEND/commit")" = "$COMMIT" ] && [ -s "$BACKEND/reshadelinux.sh" ]; then
    exit 0
fi
STAGING="$(mktemp -d "$ROOT/reshade/.backend.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT
curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 \
    "https://github.com/asafelobotomy/reshadelinux/archive/$COMMIT.tar.gz" -o "$STAGING/source.tar.gz"
printf '%s  %s\n' "$HASH" "$STAGING/source.tar.gz" | sha256sum -c -
mkdir "$STAGING/source"
# Pinned GitHub archive; never run the upstream installer during toolbox setup.
tar -xzf "$STAGING/source.tar.gz" --strip-components=1 -C "$STAGING/source"
test -s "$STAGING/source/reshadelinux.sh"
test -s "$STAGING/source/LICENSE"
printf '%s\n' "$COMMIT" > "$STAGING/source/commit"
rm -rf -- "$BACKEND"
mv -- "$STAGING/source" "$BACKEND"
