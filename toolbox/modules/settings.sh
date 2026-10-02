#!/bin/bash
settings_menu() {
    while true; do
        local choice
        choice="$(menu_select "$(i18n settings_title)" "$(i18n language_title)" \
            "fr" "Français" \
            "en" "English" \
            "0" "$(i18n back)")" || return
        case "$choice" in
            fr|en)
                WT_LANGUAGE="$choice"
                save_language
                load_i18n
                msgbox "$(i18n language_changed)" "$(i18n language_changed_body)"
                ;;
            0|"") return ;;
        esac
    done
}
