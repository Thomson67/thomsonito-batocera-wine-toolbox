#!/bin/bash

MANGOHUD_CONFIG_DIR="$WT_HOME/config"
MANGOHUD_GLOBAL_FILE="$MANGOHUD_CONFIG_DIR/mangohud-global"
MANGOHUD_OVERRIDE_FILE="$MANGOHUD_CONFIG_DIR/mangohud-games.tsv"
WINDOWS_ROMS="/userdata/roms/windows"

mangohud_global_state() {
    local v="0"
    [ -s "$MANGOHUD_GLOBAL_FILE" ] && v="$(head -n1 "$MANGOHUD_GLOBAL_FILE" | tr -d '\r\n[:space:]')"
    case "$v" in 1|on|ON|true|TRUE) printf '%s' "$(i18n enabled)" ;; *) printf '%s' "$(i18n disabled)" ;; esac
}

mangohud_set_global() {
    local value="$1"
    mkdir -p "$MANGOHUD_CONFIG_DIR"
    printf '%s\n' "$value" > "$MANGOHUD_GLOBAL_FILE"
    if [ "$value" = "1" ]; then
        msgbox "$(i18n mangohud_title)" "$(i18n mangohud_global_enabled)"
    else
        msgbox "$(i18n mangohud_title)" "$(i18n mangohud_global_disabled)"
    fi
}

mangohud_game_override() {
    local path="$1"
    [ -s "$MANGOHUD_OVERRIDE_FILE" ] || { printf '%s' "inherit"; return; }
    local v
    v="$(awk -F '\t' -v p="$path" '$2==p {v=$1} END{print v}' "$MANGOHUD_OVERRIDE_FILE")"
    case "$v" in on|off) printf '%s' "$v" ;; *) printf '%s' "inherit" ;; esac
}

mangohud_override_label() {
    case "$1" in
        on) printf '%s' "$(i18n enabled)" ;;
        off) printf '%s' "$(i18n disabled)" ;;
        *) printf '%s' "$(i18n mangohud_inherit)" ;;
    esac
}

mangohud_set_game_override() {
    local path="$1" state="$2" tmp
    mkdir -p "$MANGOHUD_CONFIG_DIR"
    tmp="$(mktemp /tmp/wt-mangohud-overrides.XXXXXX)" || return 1

    if [ -s "$MANGOHUD_OVERRIDE_FILE" ]; then
        awk -F '\t' -v p="$path" '$2!=p' "$MANGOHUD_OVERRIDE_FILE" > "$tmp"
    fi

    case "$state" in
        on|off) printf '%s\t%s\n' "$state" "$path" >> "$tmp" ;;
    esac

    mv -f "$tmp" "$MANGOHUD_OVERRIDE_FILE"
}

mangohud_list_games() {
    [ -d "$WINDOWS_ROMS" ] || return 0
    find "$WINDOWS_ROMS" -mindepth 1 \
        \( -type d \( -iname '*.pc' -o -iname '*.wine' \) -print -prune \) -o \
        \( -type f \( -iname '*.wsquashfs' -o -iname '*.wtgz' \) -print \) \
        2>/dev/null | sort -f
}

mangohud_game_menu() {
    local rows="" path state label choice idx=1 selected
    local -a items=()

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        state="$(mangohud_game_override "$path")"
        label="$(basename "$path") | $(mangohud_override_label "$state")"
        items+=("$idx" "$label")
        rows+="$path"$'\n'
        idx=$((idx+1))
    done < <(mangohud_list_games)

    if [ "${#items[@]}" -eq 0 ]; then
        msgbox "$(i18n mangohud_per_game)" "$(i18n mangohud_no_games)"
        return
    fi

    choice="$(menu_select "$(i18n mangohud_per_game)" "$(i18n mangohud_choose_game)" "${items[@]}" "0" "$(i18n back)")" || return
    [ "$choice" != "0" ] && [ -n "$choice" ] || return
    selected="$(sed -n "${choice}p" <<< "$rows")"
    [ -n "$selected" ] || return

    while true; do
        state="$(mangohud_game_override "$selected")"
        choice="$(menu_select "$(basename "$selected")" "$(i18n mangohud_game_status "$(mangohud_override_label "$state")")" \
            "1" "$(i18n mangohud_enable_game)" \
            "2" "$(i18n mangohud_disable_game)" \
            "3" "$(i18n mangohud_use_global)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) mangohud_set_game_override "$selected" on; msgbox "$(i18n mangohud_title)" "$(i18n mangohud_game_enabled "$(basename "$selected")")"; return ;;
            2) mangohud_set_game_override "$selected" off; msgbox "$(i18n mangohud_title)" "$(i18n mangohud_game_disabled "$(basename "$selected")")"; return ;;
            3) mangohud_set_game_override "$selected" inherit; msgbox "$(i18n mangohud_title)" "$(i18n mangohud_game_inherit "$(basename "$selected")")"; return ;;
            0|"") return ;;
        esac
    done
}

graphics_menu() {
    while true; do
        local choice
        choice="$(menu_select "$(i18n graphics_title)" \
            "$(i18n mangohud_intro)\n\n$(i18n mangohud_global_status "$(mangohud_global_state)")" \
            "1" "$(i18n mangohud_enable_global)" \
            "2" "$(i18n mangohud_disable_global)" \
            "3" "$(i18n mangohud_per_game)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) mangohud_set_global 1 ;;
            2) mangohud_set_global 0 ;;
            3) mangohud_game_menu ;;
            0|"") return ;;
        esac
    done
}
