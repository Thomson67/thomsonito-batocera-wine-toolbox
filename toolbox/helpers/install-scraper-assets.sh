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

mkdir -p "$PORTS_DIR" "$STATE_DIR"
old_manifest="$MANIFEST"
new_manifest="$STATE_DIR/.scraper-assets.sha256.$$"
: > "$new_manifest"

install_asset() {
    local source_file="$1" target_rel="$2"
    local source="$SRC_DIR/$source_file" target="$PORTS_DIR/$target_rel"
    local new_hash old_hash current_hash
    mkdir -p "$(dirname "$target")"
    new_hash="$(sha256sum "$source" | awk '{print $1}')"
    old_hash=""
    if [ -s "$old_manifest" ]; then
        old_hash="$(awk -v n="$target_rel" '$2 == n { print $1; exit }' "$old_manifest")"
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
    printf '%s %s\n' "$new_hash" "$target_rel" >> "$new_manifest"
}

# Batocera's standard gamelist layout uses media subdirectories relative to
# the Ports folder. Keep the existing source PNGs and point each field there.
install_asset box2d.png "media/images/$SLUG.png"
install_asset box2d.png "media/box2d/$SLUG.png"
install_asset fanart.png "media/fanarts/$SLUG.png"
install_asset logo.png "media/marquee/$SLUG.png"
install_asset screenshot.png "media/thumbnails/$SLUG.png"
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
if root.tag != "gameList":
    print("scraper-assets: gamelist.xml root is not <gameList>; leaving it untouched", file=sys.stderr)
    raise SystemExit(2)

media = {
    "image": f"./media/images/{slug}.png",
    "boxart": f"./media/box2d/{slug}.png",
    "fanart": f"./media/fanarts/{slug}.png",
    "marquee": f"./media/marquee/{slug}.png",
    "thumbnail": f"./media/thumbnails/{slug}.png",
}
fields = {
    "path": f"./{rom_name}",
    "name": title,
    "desc": desc,
    "developer": "Thomson",
    "genre": genre,
    **media,
}

def make_entry():
    return "  <game>\n" + "".join(
        f"    <{key}>{escape(value)}</{key}>\n" for key, value in fields.items()
    ) + "  </game>\n"

def set_if_empty_or_managed(body, key, value):
    """Fill blank fields; update only the old paths this installer wrote."""
    tag = re.compile(rf"(<{re.escape(key)}\b[^>]*>)(.*?)(</{re.escape(key)}\s*>)", re.DOTALL)
    self_closing = re.compile(rf"<{re.escape(key)}\b[^>]*/\s*>")
    managed_old = {
        "image": f"./images/{slug}-box2d.png",
        "fanart": f"./images/{slug}-fanart.png",
        "marquee": f"./images/{slug}-logo.png",
        "thumbnail": f"./images/{slug}-screenshot.png",
    }.get(key)
    changed = False

    def replace_tag(match):
        nonlocal changed
        old_value = match.group(2)
        plain = re.sub(r"<[^>]+>", "", old_value).strip()
        if plain and plain != managed_old:
            return match.group(0)
        if plain == value:
            return match.group(0)
        changed = True
        return match.group(1) + escape(value) + match.group(3)

    updated, count = tag.subn(replace_tag, body)
    if count:
        return updated, changed

    updated, count = self_closing.subn(f"<{key}>{escape(value)}</{key}>", body, count=1)
    if count:
        return updated, True

    updated = body
    if updated and not updated.endswith("\n"):
        updated += "\n"
    return updated + f"    <{key}>{escape(value)}</{key}>\n", True

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
        block_changed = False
        for key, value in fields.items():
            body, did_change = set_if_empty_or_managed(body, key, value)
            block_changed = block_changed or did_change
        if block_changed:
            changed = True
            print(f"scraper-assets: corrected missing/managed fields for {rom_name}")
            return match.group(1) + body + match.group(3)
        return block

    updated, _ = game_pattern.subn(update_existing, text)
    if found:
        text = updated
    else:
        close = re.search(r"</gameList\s*>", text)
        if not close:
            print("scraper-assets: gamelist.xml has no gameList closing tag; leaving it untouched", file=sys.stderr)
            raise SystemExit(2)
        before = text[:close.start()]
        if before and not before.endswith("\n"):
            before += "\n"
        text = before + make_entry() + text[close.start():]
        changed = True
else:
    close = re.search(r"</gameList\s*>", text)
    if not close:
        print("scraper-assets: gamelist.xml has no gameList closing tag; leaving it untouched", file=sys.stderr)
        raise SystemExit(2)
    text = text[:close.start()] + make_entry() + text[close.start():]
    changed = True

if not changed:
    print(f"scraper-assets: gamelist entry already has the target metadata for {rom_name}")
    raise SystemExit(0)

if not new_file:
    os.makedirs(backup_dir, exist_ok=True)
    stamp = __import__("time").strftime("%Y%m%d-%H%M%S")
    backup = os.path.join(backup_dir, f"gamelist-scraper-{stamp}-{os.getpid()}.xml")
    shutil.copy2(gamelist, backup)

fd, temp_path = tempfile.mkstemp(prefix=".gamelist-scraper-", dir=os.path.dirname(gamelist), text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    if not new_file:
        os.chmod(temp_path, os.stat(gamelist).st_mode & 0o777)
    os.replace(temp_path, gamelist)
except Exception:
    try:
        os.unlink(temp_path)
    except OSError:
        pass
    raise
print(f"scraper-assets: updated Batocera gamelist entry for {rom_name}")
PYTHON
