#!/bin/bash
github_latest_release_tag() {
    local repo="$1" url tag
    url="$(curl -fsSL --connect-timeout 5 --max-time 15 \
        -o /dev/null -w '%{url_effective}' \
        "https://github.com/$repo/releases/latest" 2>/dev/null)" || return 1
    tag="$(basename "$url")"
    [ -n "$tag" ] || return 1
    printf '%s' "$tag"
}
