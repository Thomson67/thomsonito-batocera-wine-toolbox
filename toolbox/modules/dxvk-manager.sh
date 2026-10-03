#!/bin/bash

DXVK_BUNDLE_ROOT="$WT_HOME/dxvk"
DXVK_BUNDLE_DIR="$DXVK_BUNDLE_ROOT/bundles"
DXVK_CACHE_DIR="$DXVK_BUNDLE_ROOT/cache"
BATOCERA_DXVK_PATH="/userdata/system/wine/dxvk"

dxvk_ensure_dirs() {
    mkdir -p "$DXVK_BUNDLE_DIR" "$DXVK_CACHE_DIR"
}

dxvk_active_bundle() {
    local target
    [ -L "$BATOCERA_DXVK_PATH" ] || return 0
    target="$(readlink -f "$BATOCERA_DXVK_PATH" 2>/dev/null || true)"
    case "$target" in
        "$DXVK_BUNDLE_DIR"/*) basename "$target" ;;
    esac
}

dxvk_status() {
    local active
    active="$(dxvk_active_bundle)"
    if [ -n "$active" ]; then
        printf '%s' "$active"
    elif [ -e "$BATOCERA_DXVK_PATH" ] || [ -L "$BATOCERA_DXVK_PATH" ]; then
        printf '%s' "$(i18n dxvk_external_custom)"
    else
        printf '%s' "$(i18n dxvk_batocera_default)"
    fi
}

dxvk_release_catalog() {
    local repo="$1" kind="$2" cache="$DXVK_CACHE_DIR/${kind}.json"
    dxvk_ensure_dirs

    if [ ! -s "$cache" ] || [ $(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) )) -gt 21600 ]; then
        if curl -fsSL --retry 3 --connect-timeout 15 \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/$repo/releases?per_page=100" \
            -o "$cache.tmp"; then
            mv -f "$cache.tmp" "$cache"
        else
            rm -f "$cache.tmp"
            [ -s "$cache" ] || return 1
        fi
    fi

    python3 - "$cache" "$kind" <<'PY'
import json, sys
path, kind = sys.argv[1:3]
with open(path, encoding="utf-8") as f:
    releases = json.load(f)

for rel in releases:
    if rel.get("draft") or rel.get("prerelease"):
        continue
    tag = rel.get("tag_name", "")
    version = tag[1:] if tag.startswith("v") else tag
    expected = f"dxvk-{version}.tar.gz" if kind == "dxvk" else f"vkd3d-proton-{version}.tar.zst"
    asset = next((a for a in rel.get("assets", []) if a.get("name") == expected), None)
    if asset:
        print("\t".join([tag, asset.get("browser_download_url", ""), asset.get("digest") or ""]))
PY
}

dxvk_choose_release() {
    local repo="$1" kind="$2" title="$3"
    local data line tag url digest idx=1 choice
    local -a items=()

    data="$(dxvk_release_catalog "$repo" "$kind")" || {
        msgbox "$title" "$(i18n dxvk_release_fetch_failed)"
        return 1
    }

    while IFS=$'\t' read -r tag url digest; do
        [ -n "$tag" ] && [ -n "$url" ] || continue
        items+=("$idx" "$tag")
        idx=$((idx+1))
    done <<< "$data"

    [ "${#items[@]}" -gt 0 ] || {
        msgbox "$title" "$(i18n dxvk_release_fetch_failed)"
        return 1
    }

    choice="$(menu_select "$title" "$(i18n dxvk_choose_release)" "${items[@]}" "0" "$(i18n back)")" || return 1
    [ "$choice" != "0" ] && [ -n "$choice" ] || return 1

    line="$(sed -n "${choice}p" <<< "$data")"
    printf '%s\n' "$line"
}

dxvk_verify_digest() {
    local file="$1" digest="$2"
    [ -n "$digest" ] || return 0
    case "$digest" in
        sha256:*)
            printf '%s  %s\n' "${digest#sha256:}" "$file" | sha256sum -c - >/dev/null 2>&1
            ;;
        *) return 0 ;;
    esac
}

dxvk_extract_vkd3d() {
    local archive="$1" dest="$2"
    tar -xf "$archive" -C "$dest" >/dev/null 2>&1 && return 0
    if command -v unzstd >/dev/null 2>&1; then
        unzstd -c "$archive" 2>/dev/null | tar -xf - -C "$dest" >/dev/null 2>&1
        return $?
    fi
    return 1
}

dxvk_build_bundle() {
    local dxvk_line="$1" vkd3d_line="$2"
    local dxvk_tag dxvk_url dxvk_digest vkd3d_tag vkd3d_url vkd3d_digest
    local dxvk_ver vkd3d_ver bundle_name target tmp dxvk_arc vkd3d_arc
    local dxvk_x64 dxvk_x32 vkd3d_x64 vkd3d_x86 dll

    IFS=$'\t' read -r dxvk_tag dxvk_url dxvk_digest <<< "$dxvk_line"
    IFS=$'\t' read -r vkd3d_tag vkd3d_url vkd3d_digest <<< "$vkd3d_line"

    dxvk_ver="${dxvk_tag#v}"
    vkd3d_ver="${vkd3d_tag#v}"
    bundle_name="DXVK-${dxvk_ver}__VKD3D-${vkd3d_ver}"
    target="$DXVK_BUNDLE_DIR/$bundle_name"

    if [ -d "$target" ]; then
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_bundle_exists "$bundle_name")"
        return 0
    fi

    tmp="$(mktemp -d /tmp/wt-dxvk.XXXXXX)" || return 1
    dxvk_arc="$tmp/dxvk.tar.gz"
    vkd3d_arc="$tmp/vkd3d.tar.zst"

    msgbox "$(i18n dxvk_title)" "$(i18n dxvk_downloading "$dxvk_tag" "$vkd3d_tag")"

    curl -fL --retry 3 --connect-timeout 15 "$dxvk_url" -o "$dxvk_arc" || {
        rm -rf "$tmp"
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_download_failed)"
        return 1
    }
    curl -fL --retry 3 --connect-timeout 15 "$vkd3d_url" -o "$vkd3d_arc" || {
        rm -rf "$tmp"
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_download_failed)"
        return 1
    }

    dxvk_verify_digest "$dxvk_arc" "$dxvk_digest" || {
        rm -rf "$tmp"
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_checksum_failed "DXVK $dxvk_tag")"
        return 1
    }
    dxvk_verify_digest "$vkd3d_arc" "$vkd3d_digest" || {
        rm -rf "$tmp"
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_checksum_failed "VKD3D-Proton $vkd3d_tag")"
        return 1
    }

    mkdir -p "$tmp/dxvk" "$tmp/vkd3d"
    tar -xzf "$dxvk_arc" -C "$tmp/dxvk" >/dev/null 2>&1 || {
        rm -rf "$tmp"
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_extract_failed "DXVK")"
        return 1
    }
    dxvk_extract_vkd3d "$vkd3d_arc" "$tmp/vkd3d" || {
        rm -rf "$tmp"
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_extract_failed "VKD3D-Proton")"
        return 1
    }

    dxvk_x64="$(find "$tmp/dxvk" -type f -path '*/x64/d3d11.dll' -printf '%h\n' -quit)"
    dxvk_x32="$(find "$tmp/dxvk" -type f -path '*/x32/d3d11.dll' -printf '%h\n' -quit)"
    vkd3d_x64="$(find "$tmp/vkd3d" -type f -path '*/x64/d3d12.dll' -printf '%h\n' -quit)"
    vkd3d_x86="$(find "$tmp/vkd3d" -type f \( -path '*/x86/d3d12.dll' -o -path '*/x32/d3d12.dll' \) -printf '%h\n' -quit)"

    if [ -z "$dxvk_x64" ] || [ -z "$dxvk_x32" ] || [ -z "$vkd3d_x64" ] || [ -z "$vkd3d_x86" ]; then
        rm -rf "$tmp"
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_invalid_archives)"
        return 1
    fi

    mkdir -p "$target/x64" "$target/x32"

    for dll in d3d9.dll d3d10core.dll d3d11.dll dxgi.dll; do
        cp -f "$dxvk_x64/$dll" "$target/x64/" || { rm -rf "$target" "$tmp"; return 1; }
        cp -f "$dxvk_x32/$dll" "$target/x32/" || { rm -rf "$target" "$tmp"; return 1; }
    done

    [ -f "$dxvk_x32/d3d8.dll" ] && cp -f "$dxvk_x32/d3d8.dll" "$target/x32/"

    for dll in d3d12.dll d3d12core.dll; do
        cp -f "$vkd3d_x64/$dll" "$target/x64/" || { rm -rf "$target" "$tmp"; return 1; }
        cp -f "$vkd3d_x86/$dll" "$target/x32/" || { rm -rf "$target" "$tmp"; return 1; }
    done

    cat > "$target/bundle.conf" <<EOF
DXVK_VERSION=$dxvk_ver
VKD3D_VERSION=$vkd3d_ver
DXVK_URL=$dxvk_url
VKD3D_URL=$vkd3d_url
EOF

    rm -rf "$tmp"
    msgbox "$(i18n dxvk_title)" "$(i18n dxvk_bundle_installed "$bundle_name")"
}

dxvk_install_bundle_menu() {
    local dxvk_line vkd3d_line
    dxvk_line="$(dxvk_choose_release "doitsujin/dxvk" "dxvk" "$(i18n dxvk_choose_dxvk)")" || return
    vkd3d_line="$(dxvk_choose_release "HansKristian-Work/vkd3d-proton" "vkd3d" "$(i18n dxvk_choose_vkd3d)")" || return
    dxvk_build_bundle "$dxvk_line" "$vkd3d_line"
}

dxvk_list_bundles() {
    dxvk_ensure_dirs
    find "$DXVK_BUNDLE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V
}

dxvk_activate_bundle() {
    local name="$1" target="$DXVK_BUNDLE_DIR/$1" backup

    [ -d "$target/x64" ] && [ -d "$target/x32" ] || return 1
    mkdir -p "$(dirname "$BATOCERA_DXVK_PATH")"

    if [ -e "$BATOCERA_DXVK_PATH" ] && [ ! -L "$BATOCERA_DXVK_PATH" ]; then
        yesno "$(i18n dxvk_title)" "$(i18n dxvk_existing_custom)" || return 1
        backup="$DXVK_BUNDLE_ROOT/manual-backup-$(date +%Y%m%d-%H%M%S)"
        mv "$BATOCERA_DXVK_PATH" "$backup" || return 1
    elif [ -L "$BATOCERA_DXVK_PATH" ]; then
        rm -f "$BATOCERA_DXVK_PATH" || return 1
    fi

    ln -s "$target" "$BATOCERA_DXVK_PATH" || return 1
    msgbox "$(i18n dxvk_title)" "$(i18n dxvk_global_enabled "$name")"
}

dxvk_choose_global_menu() {
    local rows="" name idx=1 choice selected
    local -a items=()

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        items+=("$idx" "$name")
        rows+="$name"$'\n'
        idx=$((idx+1))
    done < <(dxvk_list_bundles)

    if [ "${#items[@]}" -eq 0 ]; then
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_no_bundles)"
        return
    fi

    choice="$(menu_select "$(i18n dxvk_choose_global)" "$(i18n dxvk_choose_global_prompt)" "${items[@]}" "0" "$(i18n back)")" || return
    [ "$choice" != "0" ] && [ -n "$choice" ] || return
    selected="$(sed -n "${choice}p" <<< "$rows")"
    [ -n "$selected" ] && dxvk_activate_bundle "$selected"
}

dxvk_use_batocera_default() {
    local target

    if [ -L "$BATOCERA_DXVK_PATH" ]; then
        target="$(readlink -f "$BATOCERA_DXVK_PATH" 2>/dev/null || true)"
        case "$target" in
            "$DXVK_BUNDLE_DIR"/*)
                rm -f "$BATOCERA_DXVK_PATH" || return 1
                msgbox "$(i18n dxvk_title)" "$(i18n dxvk_batocera_restored)"
                return
                ;;
        esac
    fi

    if [ -e "$BATOCERA_DXVK_PATH" ] || [ -L "$BATOCERA_DXVK_PATH" ]; then
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_external_not_removed)"
    else
        msgbox "$(i18n dxvk_title)" "$(i18n dxvk_batocera_restored)"
    fi
}

dxvk_remove_bundles_menu() {
    local active rows="" name idx=1 selected="" id path failures=0
    local -a items=()

    active="$(dxvk_active_bundle)"

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if [ "$name" = "$active" ]; then
            items+=("$idx" "$name | $(i18n dxvk_active)" "off")
        else
            items+=("$idx" "$name" "off")
        fi
        rows+="$name"$'\n'
        idx=$((idx+1))
    done < <(dxvk_list_bundles)

    [ "${#items[@]}" -gt 0 ] || {
        msgbox "$(i18n dxvk_manage)" "$(i18n dxvk_no_bundles)"
        return
    }

    selected="$(checklist_select "$(i18n dxvk_manage)" "$(i18n dxvk_remove_prompt)" "${items[@]}")" || return
    [ -n "$selected" ] || return

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        name="$(sed -n "${id}p" <<< "$rows")"
        [ -n "$name" ] || continue
        if [ "$name" = "$active" ]; then
            failures=$((failures+1))
            continue
        fi
        path="$DXVK_BUNDLE_DIR/$name"
        case "$path" in "$DXVK_BUNDLE_DIR"/*) rm -rf -- "$path" || failures=$((failures+1)) ;; esac
    done <<< "$selected"

    if [ "$failures" -eq 0 ]; then
        msgbox "$(i18n dxvk_manage)" "$(i18n dxvk_remove_done)"
    else
        msgbox "$(i18n dxvk_manage)" "$(i18n dxvk_remove_partial)"
    fi
}

dxvk_manager_menu() {
    while true; do
        local choice
        choice="$(menu_select "$(i18n dxvk_title)" \
            "$(i18n dxvk_intro)\n\n$(i18n dxvk_global_status "$(dxvk_status)")" \
            "1" "$(i18n dxvk_install_bundle)" \
            "2" "$(i18n dxvk_choose_global)" \
            "3" "$(i18n dxvk_manage)" \
            "4" "$(i18n dxvk_use_batocera)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) dxvk_install_bundle_menu ;;
            2) dxvk_choose_global_menu ;;
            3) dxvk_remove_bundles_menu ;;
            4) dxvk_use_batocera_default ;;
            0|"") return ;;
        esac
    done
}
