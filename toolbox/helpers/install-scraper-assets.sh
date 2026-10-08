#!/bin/bash
set -euo pipefail

SRC_DIR="${1:?Usage: install-scraper-assets.sh SOURCE_DIR SLUG ROM_NAME TITLE DESC_FR DESC_EN STATE_DIR BACKUP_DIR}"
SLUG="${2:?missing scraper slug}"
ROM_NAME="${3:?missing Ports launcher name}"
TITLE="${4:?missing display title}"
DESC_FR="${5:?missing French description}"
DESC_EN="${6:?missing English description}"
STATE_DIR="${7:?missing persistent state directory}"
BACKUP_DIR="${8:?missing backup directory}"
PORTS_DIR="${SCRAPER_PORTS_DIR:-/userdata/roms/ports}"
IMAGE_DIR="$PORTS_DIR/images"
MANIFEST="$STATE_DIR/scraper-assets.sha256"

fail() { printf 'scraper-assets: %s\n' "$*" >&2; exit 1; }

[ -d "$SRC_DIR" ] || fail "asset directory missing: $SRC_DIR"
for file in box2d.png fanart.png logo.png screenshot.png; do
    [ -s "$SRC_DIR/$file" ] || fail "required asset missing: $SRC_DIR/$file"
done

case "$(batocera-settings-get system.language 2>/dev/null || true)" in
    fr*|FR*) DESC="$DESC_FR"; GENRE="Utilitaire" ;;
    *) DESC="$DESC_EN"; GENRE="Utility" ;;
esac

mkdir -p "$IMAGE_DIR" "$STATE_DIR"
old_manifest="$MANIFEST"
new_manifest="$STATE_DIR/.scraper-assets.sha256.$$"
: > "$new_manifest"

for file in box2d.png fanart.png logo.png screenshot.png; do
    source="$SRC_DIR/$file"
    target_name="$SLUG-$file"
    target="$IMAGE_DIR/$target_name"
    new_hash="$(sha256sum "$source" | awk '{print $1}')"
    old_hash=""
    if [ -s "$old_manifest" ]; then
        old_hash="$(awk -v n="$target_name" '$2 == n { print $1; exit }' "$old_manifest")"
    fi

    if [ -L "$target" ]; then
        printf 'scraper-assets: preserving linked custom media %s\n' "$target"
    elif [ -e "$target" ]; then
        current_hash="$(sha256sum "$target" | awk '{print $1}')"
        if [ "$current_hash" = "$new_hash" ] || { [ -n "$old_hash" ] && [ "$current_hash" = "$old_hash" ]; }; then
            cp -f -- "$source" "$target" || fail "could not update $target"
        else
            printf 'scraper-assets: preserving custom media %s\n' "$target"
        fi
    else
        cp -p -- "$source" "$target" || fail "could not install $target"
    fi
    printf '%s %s\n' "$new_hash" "$target_name" >> "$new_manifest"
done
mv -f -- "$new_manifest" "$MANIFEST" || fail "could not update asset manifest"

python3 - "$PORTS_DIR/gamelist.xml" "$BACKUP_DIR" "$ROM_NAME" "$TITLE" "$DESC" "$GENRE" "$SLUG" <<'PYTHON'
import os
import re
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

gamelist, backup_dir, rom_name, title, desc, genre, slug = sys.argv[1:]
new_file = not os.path.exists(gamelist)
if new_file:
    text = '<?xml version="1.0"?>\n<gameList>\n</gameList>\n'
else:
    with open(gamelist, "r", encoding="utf-8") as f:
        text = f.read()

try:
    root = ET.fromstring(text)
except ET.ParseError as exc:
    print(f"scraper-assets: gamelist.xml is invalid; leaving it untouched: {exc}", file=sys.stderr)
    raise SystemExit(2)

media = {
    "image": f"./images/{slug}-box2d.png",
    "fanart": f"./images/{slug}-fanart.png",
    "marquee": f"./images/{slug}-logo.png",
    "thumbnail": f"./images/{slug}-screenshot.png",
}
fields = {
    "path": f"./{rom_name}",
    "name": title,
    "desc": desc,
    "developer": "Thomson",
    "genre": genre,
    **media,
}
entry = "  <game>\n" + "".join(
    f"    <{key}>{escape(value)}</{key}>\n" for key, value in fields.items()
) + "  </game>\n"
close = re.search(r"</gameList\s*>", text)
if not close:
    print("scraper-assets: gamelist.xml has no gameList closing tag; leaving it untouched", file=sys.stderr)
    raise SystemExit(2)

changed = False
found = False
if not new_file:
    game_pattern = re.compile(r"(<game(?:\s[^>]*)?>)(.*?)(</game>)", re.DOTALL)
    def update_existing(match):
        global changed, found
        block = match.group(0)
        try:
            game = ET.fromstring(block)
        except ET.ParseError:
            return block
        path = game.findtext("path", default="").replace("\\", "/").rstrip("/")
        if os.path.basename(path) != rom_name:
            return block
        found = True
        body = match.group(2)
        present = {child.tag for child in game}
        missing = {key: value for key, value in fields.items() if key not in present}
        if not missing:
            print(f"scraper-assets: preserving complete gamelist entry for {rom_name}")
            return block
        additions = "".join(f"    <{key}>{escape(value)}</{key}>\n" for key, value in missing.items())
        if body and not body.endswith("\n"):
            body += "\n"
        changed = True
        print(f"scraper-assets: filling missing gamelist fields for {rom_name}")
        return match.group(1) + body + additions + match.group(3)

    updated, _ = game_pattern.subn(update_existing, text)
    if found and not changed:
        print(f"scraper-assets: preserving complete gamelist entry for {rom_name}")
        raise SystemExit(0)
    if found and changed:
        text = updated
    elif not found:
        before = text[:close.start()]
        if before and not before.endswith("\n"):
            before += "\n"
        text = before + entry + text[close.start():]
        changed = True
else:
    text = text[:close.start()] + entry + text[close.start():]
    changed = True

if not changed:
    raise SystemExit(0)

if not new_file:
    os.makedirs(backup_dir, exist_ok=True)
    stamp = __import__("time").strftime("%Y%m%d-%H%M%S")
    backup = os.path.join(backup_dir, f"gamelist-scraper-{stamp}-{os.getpid()}.xml")
    shutil.copy2(gamelist, backup)

updated = text
directory = os.path.dirname(gamelist)
fd, temp_path = tempfile.mkstemp(prefix=".gamelist-scraper-", dir=directory, text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
        f.write(updated)
    if not new_file:
        os.chmod(temp_path, os.stat(gamelist).st_mode & 0o777)
    os.replace(temp_path, gamelist)
except Exception:
    try:
        os.unlink(temp_path)
    except OSError:
        pass
    raise
print(f"scraper-assets: added gamelist entry for {rom_name}")
PYTHON
