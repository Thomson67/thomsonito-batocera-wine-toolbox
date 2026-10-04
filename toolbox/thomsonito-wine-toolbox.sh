#!/bin/bash
set -u

WT_ROOT="$(cd "$(dirname "$0")" && pwd)"
export WT_ROOT

source "$WT_ROOT/lib/common.sh"
source "$WT_ROOT/lib/github.sh"
source "$WT_ROOT/lib/download.sh"
source "$WT_ROOT/lib/checksum.sh"
source "$WT_ROOT/lib/batocera.sh"

source "$WT_ROOT/modules/umu.sh"
source "$WT_ROOT/modules/starter-pack.sh"
source "$WT_ROOT/modules/runners.sh"
source "$WT_ROOT/modules/ge-proton-legacy.sh"
source "$WT_ROOT/modules/maintenance.sh"
source "$WT_ROOT/modules/batocera-conf.sh"
source "$WT_ROOT/modules/batocera-conf-extra.sh"
source "$WT_ROOT/modules/graphics.sh"
source "$WT_ROOT/modules/dxvk-manager.sh"
source "$WT_ROOT/modules/settings.sh"

ensure_batocera_paths

main_menu() {
    while true; do
        local choice
        choice="$(menu_select "$WT_TITLE v$(wt_version)" \
            "$(i18n app_subtitle)

$(i18n menu_umu): $(umu_toolbox_status)" \
            "1" "$(i18n menu_umu)" \
            "2" "$(i18n menu_starter)" \
            "3" "$(i18n menu_runners)" \
            "4" "$(i18n menu_graphics)" \
            "5" "$(i18n menu_maintenance)" \
            "6" "$(i18n menu_settings)" \
            "0" "$(i18n exit)")" || exit 0

        case "$choice" in
            1) umu_menu ;;
            2) starter_pack_menu ;;
            3) runner_manager_menu ;;
            4) graphics_menu ;;
            5) maintenance_menu ;;
            6) settings_menu ;;
            0|"") clear; exit 0 ;;
        esac
    done
}

main_menu
