#!/bin/bash
maintenance_menu() {
    local wine_count umu_state
    wine_count="$(find /userdata/system/wine/custom -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    umu_state="$(umu_toolbox_status)"
    msgbox "$(i18n maintenance_title)" \
        "$(i18n maintenance_body "$(batocera_version)" "$wine_count" "$umu_state")"
}
