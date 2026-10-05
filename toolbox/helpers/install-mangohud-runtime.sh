#!/bin/bash
set -euo pipefail

ROOT="/userdata/system/ultimate-wine-toolbox"
RUNTIME="$ROOT/runtime/mangohud"
LIB32="$RUNTIME/lib32/mangohud"
LIB="$RUNTIME/lib/mangohud"
LIB64="$RUNTIME/lib64/mangohud"

VERSION="0.8.4"
ASSET="MangoHud-0.8.4.r0.g992103e.tar.gz"
ASSET_SIZE="10282346"
URL="https://github.com/flightlessmango/MangoHud/releases/download/v0.8.4/$ASSET"

if [ -s "$RUNTIME/PROVENANCE.txt" ] && grep -qx "version=$VERSION" "$RUNTIME/PROVENANCE.txt" 2>/dev/null && \
   [ -s "$LIB32/libMangoHud.so" ] && [ -s "$LIB32/libMangoHud_opengl.so" ] && [ -s "$LIB32/libMangoHud_shim.so" ] && \
   [ -s "$LIB64/libMangoHud.so" ] && [ -s "$LIB64/libMangoHud_opengl.so" ] && [ -s "$LIB64/libMangoHud_shim.so" ]; then
    echo "MangoHud: runtime $VERSION already installed."
    exit 0
fi
TMP="$(mktemp -d /tmp/uwt-mangohud.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

for cmd in curl tar python3 sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "MangoHud: missing command: $cmd" >&2
        exit 1
    }
done

archive="$TMP/$ASSET"
echo "MangoHud: downloading official MangoHud $VERSION package..."
curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$archive"

actual_size="$(wc -c < "$archive" | tr -d '[:space:]')"
[ "$actual_size" = "$ASSET_SIZE" ] || {
    echo "MangoHud: unexpected archive size ($actual_size, expected $ASSET_SIZE)." >&2
    exit 1
}

tar -tzf "$archive" >/dev/null
mkdir -p "$TMP/outer"
tar -xzf "$archive" -C "$TMP/outer"

package_tar="$(find "$TMP/outer" -type f -name 'MangoHud-package.tar' -print -quit)"
[ -n "$package_tar" ] && [ -s "$package_tar" ] || {
    echo "MangoHud: MangoHud-package.tar not found." >&2
    exit 1
}

mkdir -p "$TMP/package"
tar -xf "$package_tar" -C "$TMP/package"

src32="$TMP/package/usr/lib/mangohud/lib32"
src64="$TMP/package/usr/lib/mangohud/lib64"

for lib in libMangoHud.so libMangoHud_opengl.so libMangoHud_shim.so; do
    [ -s "$src32/$lib" ] || {
        echo "MangoHud: missing 32-bit $lib in official package." >&2
        exit 1
    }
    [ -s "$src64/$lib" ] || {
        echo "MangoHud: missing 64-bit $lib in official package." >&2
        exit 1
    }
    python3 - "$src32/$lib" "$src64/$lib" <<'PY'
import sys
for path, expected in ((sys.argv[1], b"\x7fELF\x01"), (sys.argv[2], b"\x7fELF\x02")):
    with open(path, "rb") as f:
        ident=f.read(5)
    if ident != expected:
        raise SystemExit(f"{path}: unexpected ELF class")
PY
done

rm -rf "$RUNTIME"
mkdir -p "$LIB32" "$LIB64"

for lib in libMangoHud.so libMangoHud_opengl.so libMangoHud_shim.so; do
    cp -f "$src32/$lib" "$LIB32/$lib"
    cp -f "$src64/$lib" "$LIB64/$lib"
done
chmod 0644 "$LIB32/"*.so "$LIB64/"*.so

{
    echo "version=$VERSION"
    echo "source=$URL"
    echo "asset_size=$ASSET_SIZE"
    echo "installed_at=$(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "[lib32]"
    (cd "$LIB32" && sha256sum libMangoHud.so libMangoHud_opengl.so libMangoHud_shim.so)
    echo "[lib64]"
    (cd "$LIB64" && sha256sum libMangoHud.so libMangoHud_opengl.so libMangoHud_shim.so)
} > "$RUNTIME/PROVENANCE.txt"

echo "MangoHud: installed runtime $VERSION under $RUNTIME"
