#!/bin/bash

ROOT="/userdata/system/ultimate-wine-toolbox"
CONFIG_DIR="$ROOT/config"
GLOBAL_FILE="$CONFIG_DIR/mangohud-global"
OVERRIDE_FILE="$CONFIG_DIR/mangohud-games.tsv"
LEGACY_LAYER_DIR="/usr/share/vulkan/implicit_layer.d"
LEGACY_LAYER_FILE="$LEGACY_LAYER_DIR/MangoHud.ultimate-wine-toolbox.json"
LOG_DIR="/userdata/system/logs/ultimate-wine-toolbox"
HOOK_LOG="$LOG_DIR/mangohud-hook.log"

hook_log() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$HOOK_LOG" 2>/dev/null || true
}

event="${1:-}"
system="${2:-}"
rom="${5:-}"

[ "$event" = "gameStart" ] || exit 0
[ "$system" = "windows" ] || exit 0
[ -n "$rom" ] || exit 0
hook_log "event=$event system=$system rom=$rom"

batocera_major() {
    local raw=""
    if command -v batocera-version >/dev/null 2>&1; then
        raw="$(batocera-version 2>/dev/null | head -n1)"
    elif [ -r /usr/share/batocera/batocera.version ]; then
        raw="$(head -n1 /usr/share/batocera/batocera.version 2>/dev/null)"
    elif [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        raw="${PRETTY_NAME:-${VERSION_ID:-}}"
    fi
    printf '%s\n' "$raw" | grep -oE '[0-9]+' | head -n1
}

is_legacy_mangohud_batocera() {
    case "$(batocera_major)" in
        41|42) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_legacy_vulkan_layer() {
    is_legacy_mangohud_batocera || return 0
    [ -r /usr/lib/mangohud/libMangoHud.so ] || return 0

    # Batocera 41/42 ship MangoHud but omit its Vulkan implicit-layer manifest.
    # Do not add a duplicate if another manifest already exposes the same layer.
    if [ -d "$LEGACY_LAYER_DIR" ] &&        grep -Rslq '"VK_LAYER_MANGOHUD_overlay_x86_64"' "$LEGACY_LAYER_DIR" 2>/dev/null; then
        return 0
    fi

    mkdir -p "$LEGACY_LAYER_DIR" 2>/dev/null || return 0
    cat > "$LEGACY_LAYER_FILE" <<'EOF'
{
    "file_format_version": "1.0.0",
    "layer": {
        "name": "VK_LAYER_MANGOHUD_overlay_x86_64",
        "type": "GLOBAL",
        "api_version": "1.3.0",
        "library_path": "/usr/lib/mangohud/libMangoHud.so",
        "implementation_version": "1",
        "description": "Vulkan Hud Overlay (Ultimate Wine Toolbox compatibility)",
        "functions": {
            "vkGetInstanceProcAddr": "overlay_GetInstanceProcAddr",
            "vkGetDeviceProcAddr": "overlay_GetDeviceProcAddr"
        },
        "enable_environment": {
            "MANGOHUD": "1"
        },
        "disable_environment": {
            "DISABLE_MANGOHUD": "1"
        }
    }
}
EOF
}

global_state="0"
[ -s "$GLOBAL_FILE" ] && global_state="$(head -n1 "$GLOBAL_FILE" | tr -d '\r\n[:space:]')"
case "$global_state" in 1|on|ON|true|TRUE) global_state=1 ;; *) global_state=0 ;; esac

override=""
if [ -s "$OVERRIDE_FILE" ]; then
    override="$(awk -F '\t' -v p="$rom" '$2==p {v=$1} END{print v}' "$OVERRIDE_FILE")"
fi

case "$override" in
    on) desired=1 ;;
    off) desired=0 ;;
    *) desired="$global_state" ;;
esac

legacy_mangohud=0
detected_major="$(batocera_major)"
hook_log "batocera_major=${detected_major:-unknown} global=$global_state override=${override:-inherit} desired=$desired"
if is_legacy_mangohud_batocera; then
    legacy_mangohud=1
    if [ "$desired" = "1" ]; then
        ensure_legacy_vulkan_layer
        if [ -s "$LEGACY_LAYER_FILE" ]; then
            hook_log "legacy_vulkan_layer=created path=$LEGACY_LAYER_FILE"
        elif grep -Rslq '"VK_LAYER_MANGOHUD_overlay_x86_64"' "$LEGACY_LAYER_DIR" 2>/dev/null; then
            hook_log "legacy_vulkan_layer=already_present"
        else
            hook_log "legacy_vulkan_layer=missing"
        fi
    fi
fi

rewrite_autorun() {
    local file="$1" state="$2" legacy="$3"
    [ -f "$file" ] || return 1

    python3 - "$file" "$state" "$legacy" <<'PY'
import re, sys
from pathlib import Path

path=Path(sys.argv[1])
enabled=sys.argv[2] == "1"
legacy=sys.argv[3] == "1"
managed_preload="/usr/$LIB/mangohud/libMangoHud_opengl.so"

try:
    text=path.read_text(encoding="utf-8", errors="replace")
except Exception:
    raise SystemExit(1)

lines=text.replace("\r\n","\n").replace("\r","\n").split("\n")
out=[]
found=False

def clean_payload(payload):
    payload=re.sub(r'(^|\s)MANGOHUD=[^\s]+', ' ', payload)
    # Remove only the LD_PRELOAD value managed by this Toolbox. Never touch a
    # different/custom LD_PRELOAD supplied by the user.
    payload=re.sub(
        r'(^|\s)LD_PRELOAD=(?:[\'"])?/usr/\$LIB/mangohud/libMangoHud_opengl\.so(?:[\'"])?(?=\s|$)',
        ' ',
        payload
    )
    return re.sub(r'\s+', ' ', payload).strip()

for line in lines:
    if line.startswith("ENV=") and not found:
        payload=clean_payload(line[4:])
        if enabled:
            payload=(payload + " " if payload else "") + "MANGOHUD=1"
            # Batocera 41/42 need the OpenGL preload used by their native
            # /usr/bin/mangohud wrapper. Preserve any user-supplied LD_PRELOAD.
            if legacy and not re.search(r'(^|\s)LD_PRELOAD=', payload):
                payload += " LD_PRELOAD='" + managed_preload + "'"
        if payload:
            out.append("ENV="+payload)
        found=True
    else:
        out.append(line)

if enabled and not found:
    payload="MANGOHUD=1"
    if legacy:
        payload += " LD_PRELOAD='" + managed_preload + "'"
    insert_at=0
    for i,line in enumerate(out):
        if line.startswith(("DIR=","CMD=","LANG=","SAVEDIR=","SAVEFILES=")):
            insert_at=i
            break
    out.insert(insert_at, "ENV="+payload)

while out and out[-1] == "":
    out.pop()
path.write_text("\n".join(out)+"\n", encoding="utf-8")
PY
}

get_runner() {
    local romname="$1" runner
    runner="$(batocera-settings-get "windows[\"$romname\"].wine-runner" "windows.wine-runner" "global.wine-runner" 2>/dev/null || true)"
    if [ -z "$runner" ]; then
        runner="$(batocera-settings-get "windows[\"$romname\"].core" "windows.core" "global.core" 2>/dev/null || true)"
    fi
    case "$runner" in
        lutris) runner="wine-tkg" ;;
        proton) runner="wine-proton" ;;
        "") runner="wine-tkg" ;;
    esac
    printf '%s' "$runner"
}

case "${rom,,}" in
    *.pc|*.wine)
        [ -d "$rom" ] || exit 0
        rewrite_autorun "$rom/autorun.cmd" "$desired" "$legacy_mangohud" || true
        ;;
    *.wsquashfs)
        [ -f "$rom" ] || exit 0
        romname="$(basename "$rom")"

        if [ "$legacy_mangohud" = "1" ]; then
            # Batocera 41/42 use the game basename directly as the OverlayFS
            # upperdir, with no runner subdirectory and no .wine suffix.
            upper="/userdata/system/wine-bottles/windows/$romname"
        else
            runner="$(get_runner "$romname")"
            upper="/userdata/system/wine-bottles/windows/$runner/$romname.wine"
        fi

        autorun="$upper/autorun.cmd"
        if [ ! -f "$autorun" ]; then
            tmp="$(mktemp /tmp/wt-mangohud-autorun.XXXXXX)" || exit 0
            if unsquashfs -cat "$rom" autorun.cmd > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
                mkdir -p "$upper"
                cp -f "$tmp" "$autorun"
            fi
            rm -f "$tmp"
        fi

        if [ -f "$autorun" ]; then
            rewrite_autorun "$autorun" "$desired" "$legacy_mangohud" || true
            hook_log "autorun=$autorun legacy=$legacy_mangohud rewritten=1"
        else
            hook_log "autorun=$autorun legacy=$legacy_mangohud rewritten=0"
        fi
        ;;
    *.wtgz)
        romname="$(basename "$rom")"
        runner="$(get_runner "$romname")"
        prefix="/userdata/system/wine-bottles/windows/$runner/$romname.wine"
        [ -f "$prefix/autorun.cmd" ] && rewrite_autorun "$prefix/autorun.cmd" "$desired" "$legacy_mangohud" || true
        ;;
esac

exit 0
