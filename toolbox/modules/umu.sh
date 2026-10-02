#!/bin/bash

UMU_TOOLBOX_REPO="Thomson67/umu-runner-toolbox"
UMU_TOOLBOX_ROOT="/userdata/system/umu/toolbox"
UMU_TOOLBOX_MAIN="$UMU_TOOLBOX_ROOT/umu-toolbox.sh"
UMU_TOOLBOX_VERSION_FILE="$UMU_TOOLBOX_ROOT/VERSION"

umu_toolbox_installed() { [ -x "$UMU_TOOLBOX_MAIN" ]; }

umu_toolbox_version() {
    [ -s "$UMU_TOOLBOX_VERSION_FILE" ] \
        && tr -d '\r\n[:space:]' < "$UMU_TOOLBOX_VERSION_FILE" \
        || printf '%s' "$(i18n unknown)"
}

umu_toolbox_status() {
    if umu_toolbox_installed; then
        printf '%s - v%s' "$(i18n installed)" "$(umu_toolbox_version)"
    else
        printf '%s' "$(i18n not_installed)"
    fi
}

install_umu_toolbox() {
    clear
    echo "$(i18n umu_installing)"
    echo
    curl -fsSL "https://raw.githubusercontent.com/$UMU_TOOLBOX_REPO/main/install.sh" | bash
}

ensure_umu_toolbox() {
    umu_toolbox_installed && return 0
    install_umu_toolbox || {
        msgbox "$(i18n menu_umu)" "$(i18n umu_install_failed)"
        return 1
    }
    umu_toolbox_installed
}

launch_umu_toolbox() {
    if ! umu_toolbox_installed; then
        msgbox "$(i18n menu_umu)" "$(i18n umu_missing)"
        return
    fi
    "$UMU_TOOLBOX_MAIN"
}

install_umu_runner() {
    local runner="$1"
    ensure_umu_toolbox || return 1
    echo "$(i18n umu_runner_installing "$runner")"
    "$UMU_TOOLBOX_MAIN" --install-runner "$runner"
}

umu_menu() {
    while true; do
        local choice
        choice="$(menu_select "$(i18n menu_umu)" \
            "$(i18n status): $(umu_toolbox_status)" \
            "1" "$(i18n umu_launch)" \
            "2" "$(i18n umu_install_update)" \
            "0" "$(i18n back)")" || return
        case "$choice" in
            1) launch_umu_toolbox ;;
            2) install_umu_toolbox ;;
            0|"") return ;;
        esac
    done
}
