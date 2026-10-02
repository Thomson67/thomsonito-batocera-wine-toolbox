#!/bin/bash
download_file() {
    local url="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    curl -fL --retry 3 --connect-timeout 15 --progress-bar "$url" -o "$dest"
}
