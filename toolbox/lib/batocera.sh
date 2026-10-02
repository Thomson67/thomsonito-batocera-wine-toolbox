#!/bin/bash
BATOCERA_CUSTOM_WINE="/userdata/system/wine/custom"
BATOCERA_PORTS="/userdata/roms/ports"

batocera_version() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        printf '%s' "${PRETTY_NAME:-Batocera}"
    else
        printf 'Batocera'
    fi
}

ensure_batocera_paths() {
    mkdir -p "$BATOCERA_CUSTOM_WINE" "$BATOCERA_PORTS"
}

free_bytes_userdata() {
    df -PB1 /userdata 2>/dev/null | awk 'NR==2 {print $4}'
}
