#!/bin/bash
set -euo pipefail

ROOT="/userdata/system/ultimate-wine-toolbox"
RUNTIME="$ROOT/runtime/mangohud"
LIB32="$RUNTIME/lib32/mangohud"

VERSION="0.7.2"
ASSET="MangoHud-0.7.2.r0.g7b80f73.tar.gz"
ASSET_SIZE="8757355"
URL="https://github.com/flightlessmango/MangoHud/releases/download/v0.7.2/$ASSET"

TMP="$(mktemp -d /tmp/uwt-mangohud32.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

for cmd in curl tar python3 sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "MangoHud32: missing command: $cmd" >&2
        exit 1
    }
done

archive="$TMP/$ASSET"
echo "MangoHud32: downloading official MangoHud $VERSION package..."
curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$archive"

actual_size="$(wc -c < "$archive" | tr -d '[:space:]')"
[ "$actual_size" = "$ASSET_SIZE" ] || {
    echo "MangoHud32: unexpected archive size ($actual_size, expected $ASSET_SIZE)." >&2
    exit 1
}

tar -tzf "$archive" >/dev/null
mkdir -p "$TMP/outer"
tar -xzf "$archive" -C "$TMP/outer"

package_tar="$(find "$TMP/outer" -type f -name 'MangoHud-package.tar' -print -quit)"
[ -n "$package_tar" ] && [ -s "$package_tar" ] || {
    echo "MangoHud32: MangoHud-package.tar not found." >&2
    exit 1
}

mkdir -p "$TMP/package"
tar -xf "$package_tar" -C "$TMP/package"

src="$TMP/package/usr/lib/mangohud/lib32"
for lib in libMangoHud.so libMangoHud_dlsym.so libMangoHud_opengl.so; do
    [ -s "$src/$lib" ] || {
        echo "MangoHud32: missing $lib in official package." >&2
        exit 1
    }
    python3 - "$src/$lib" <<'PY'
import sys
p=sys.argv[1]
with open(p, "rb") as f:
    ident=f.read(5)
if ident != b"\x7fELF\x01":
    raise SystemExit(f"{p}: expected ELF32 library")
PY
done

rm -rf "$RUNTIME"
mkdir -p "$LIB32"
cp -f "$src/libMangoHud.so" "$LIB32/libMangoHud.so"
cp -f "$src/libMangoHud_dlsym.so" "$LIB32/libMangoHud_dlsym.so"
cp -f "$src/libMangoHud_opengl.so" "$LIB32/libMangoHud_opengl.so"
chmod 0644 "$LIB32/libMangoHud.so" "$LIB32/libMangoHud_dlsym.so" "$LIB32/libMangoHud_opengl.so"

{
    echo "version=$VERSION"
    echo "source=$URL"
    echo "asset_size=$ASSET_SIZE"
    echo "installed_at=$(date '+%Y-%m-%d %H:%M:%S %z')"
    (cd "$LIB32" && sha256sum libMangoHud.so libMangoHud_dlsym.so libMangoHud_opengl.so)
} > "$RUNTIME/PROVENANCE.txt"

echo "MangoHud32: installed under $RUNTIME"
