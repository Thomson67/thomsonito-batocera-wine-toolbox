#!/bin/bash

WSQ_UPDATE_HELPER="$WT_ROOT/helpers/wsquashfs_update.py"

wsq_update_run() {
    local title="$1" body="$2" log="$3" pid start=$SECONDS rc
    have_dialog || printf '%b\n' "$body"
    shift 3
    "$@" >> "$log" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if have_dialog; then
            dialog --no-shadow --title "$title" --infobox \
                "$body\n\n$(i18n wsq_update_elapsed "$((SECONDS-start))")" 12 96
        fi
        sleep 1
    done
    wait "$pid"; rc=$?
    wt_clear_tty
    return "$rc"
}

wsq_pending_guard() {
    [ -s "$WSQ_STATE_FILE" ] || return 0
    msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_pending)"
    return 1
}

wsq_update_state() {
    python3 - "$WSQ_STATE_FILE" "$@" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
for i in range(2, len(sys.argv), 2):
    data[sys.argv[i]] = sys.argv[i + 1]
tmp = path + '.tmp'
with open(tmp, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
os.replace(tmp, path)
PY
}

wsq_update_select_executable() {
    local prefix="$1" existing choice
    existing="$(python3 "$WSQ_UPDATE_HELPER" exe "$prefix")" || return 1
    if [ -n "$existing" ]; then
        choice="$(menu_select "$(i18n wsq_executable_title)" \
            "$(i18n wsq_update_exe_prompt "$(wsq_display_path "$existing")")" \
            keep "$(i18n wsq_update_exe_keep)" other "$(i18n wsq_update_exe_other)")" || return 1
        case "$choice" in
            keep) printf '%s\n' "$existing"; return 0 ;;
            other) ;;
            *) return 1 ;;
        esac
    else
        msgbox "$(i18n wsq_executable_title)" "$(i18n wsq_update_exe_missing)"
    fi
    local game_dir
    game_dir="$(python3 "$WSQ_UPDATE_HELPER" game-dir "$prefix")" || return 1
    wsq_select_executable "$prefix" "$game_dir"
}

wsq_update_new() {
    wsq_pending_guard || return
    local archive source prefix game_name exe_rel runner snapshot metadata log choice idx=1 rows="" path stamp
    local -a items=()
    command -v unsquashfs >/dev/null 2>&1 && command -v mksquashfs >/dev/null 2>&1 || {
        msgbox "$(i18n wsq_update_title)" "$(i18n squash_tools_missing)"; return
    }
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        items+=("$idx" "$(basename "$path")")
        rows+="$path"$'\n'
        idx=$((idx+1))
    done < <(find "$WSQ_WINDOWS_DIR" -maxdepth 1 -type f -iname '*.wsquashfs' -print 2>/dev/null | sort -f)
    [ "${#items[@]}" -gt 0 ] || {
        msgbox "$(i18n wsq_update_title)" "$(i18n squash_no_wsquashfs)"; return
    }
    choice="$(menu_select "$(i18n wsq_update_title)" "$(i18n wsq_update_intro)\n\n$(i18n wsq_version_warning)" "${items[@]}")" || return
    case "$choice" in ''|*[!0-9]*) return ;; esac
    [ "$choice" -ge 1 ] && [ "$choice" -lt "$idx" ] || return
    archive="$(sed -n "${choice}p" <<< "$rows")"
    if command -v yad >/dev/null 2>&1; then
        source="$(DISPLAY="${DISPLAY:-:0}" LANGUAGE="$WT_LANGUAGE" yad --file-selection --directory \
            --filename="$WSQ_WINDOWS_DIR/" --title="$(i18n wsq_update_source_title)" --width=1000 --height=700)" || return
    else
        source="$(input_text "$(i18n wsq_update_source_title)" "$(i18n wsq_update_source_prompt)" "$WSQ_WINDOWS_DIR/")" || return
    fi
    [ -d "$source" ] || { msgbox "$(i18n wsq_update_title)" "$(i18n wsq_source_invalid "$source")"; return; }
    [ "$(maintenance_detect_wsquashfs_type "$archive")" = wine ] || {
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_prefix_required)"; return
    }
    game_name="$(basename "$archive")"; game_name="${game_name%.*}"
    stamp="$(date '+%Y%m%d-%H%M%S')-$$"
    prefix="$(dirname "$archive")/${game_name}.update-${stamp}.wine"
    [ ! -e "$prefix" ] && [ ! -L "$prefix" ] || return
    yesno_default_no "$(i18n wsq_update_title)" \
        "$(i18n wsq_update_confirm "$(wsq_display_path "$archive")" "$(wsq_display_path "$source")" "$(wsq_display_path "$prefix")")" || return
    mkdir -p "$WSQ_STATE_DIR" "$WT_LOG_DIR" || return
    metadata="$WSQ_STATE_DIR/wsquashfs-update-$stamp.json"
    log="$WT_LOG_DIR/wsquashfs-integrity-update-$stamp.log"
    : > "$log"
    wsq_integrity_rotate_logs "$log" || true
    if ! maintenance_run_progress "$(i18n wsq_update_title)" "$(i18n wsq_update_extract)" \
        unsquashfs -no-xattrs -percentage -d "$prefix" "$archive"; then
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
    fi
    if ! wsq_update_run "$(i18n wsq_update_title)" "$(i18n wsq_update_copy)" "$log" \
        python3 "$WSQ_UPDATE_HELPER" prepare "$prefix" "$source" "$archive" "$WSQ_SAVE_ROOT" "$metadata"; then
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
    fi
    exe_rel="$(wsq_update_select_executable "$prefix")" || {
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_kept "$prefix")"; return
    }
    python3 "$WSQ_UPDATE_HELPER" autorun "$prefix" "$exe_rel" >> "$log" 2>&1 || {
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
    }
    runner="$(python3 "$WSQ_UPDATE_HELPER" config "$WSQ_CONF" "$(basename "$archive")" "$(basename "$prefix")" \
        --backup-dir "$WSQ_STATE_DIR/config-backups" 2>> "$log")" || {
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
    }
    if [ "$(python3 "$WSQ_UPDATE_HELPER" root-link "$metadata")" = True ]; then
        while true; do
            choice="$(menu_select "$(i18n wsq_update_save_title)" "$(i18n wsq_update_root_prompt)" \
                continue "$(i18n wsq_update_root_continue)" \
                copy "$(i18n wsq_update_root_copy)")" || return
            [ "$choice" != continue ] || break
            [ "$choice" = copy ] || return
            if command -v yad >/dev/null 2>&1; then
                path="$(DISPLAY="${DISPLAY:-:0}" yad --file-selection --directory --filename="$WSQ_SAVE_ROOT/" \
                    --title="$(i18n wsq_update_root_copy)" --width=1000 --height=700)" || continue
            else
                path="$(input_text "$(i18n wsq_update_root_copy)" "$(i18n wsq_update_root_prompt)" "$WSQ_SAVE_ROOT/")" || continue
            fi
            if ! wsq_update_run "$(i18n wsq_update_title)" "$(i18n wsq_update_copy)" "$log" \
                python3 "$WSQ_UPDATE_HELPER" seed-legacy "$metadata" "$path"; then
                msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"
            fi
        done
    fi
    snapshot="$WSQ_STATE_DIR/wsquashfs-before-$stamp.json"
    python3 "$WSQ_HELPER" snapshot "$prefix" "$snapshot" >> "$log" 2>&1 || {
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
    }
    wsq_save_state "$prefix" "$game_name" "$snapshot" "$exe_rel" "$runner" || return
    wsq_update_state mode update metadata "$metadata" phase testing update_log "$log" || return
    msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_test "$prefix")"
    wsq_request_game_launch "$prefix" || return
    wsq_restart_emulationstation_deferred || return
    exit 0
}

wsq_update_review_save() {
    local metadata="$1" savedir savefiles choice legacy
    savedir="$(python3 "$WSQ_UPDATE_HELPER" value "$metadata" savedir)" || return 1
    savefiles="$(python3 "$WSQ_UPDATE_HELPER" value "$metadata" savefiles)" || return 1
    legacy="$(python3 "$WSQ_UPDATE_HELPER" legacy-summary "$metadata")" || return 1
    if [ -z "$savedir$savefiles" ] && [ -n "$legacy" ]; then
        while true; do
            choice="$(menu_select "$(i18n wsq_update_save_title)" \
                "$(i18n wsq_update_links_prompt "$(wsq_display_path "$legacy")")" \
                keep "$(i18n wsq_update_links_keep)" \
                detect "$(i18n wsq_update_save_detect)" \
                browse "$(i18n wsq_browser_title)" \
                retry "$(i18n wsq_no_save_retry)" \
                cancel "$(i18n wsq_launch_cancel)")" || return 1
            case "$choice" in
                keep)
                    yesno_default_no "$(i18n wsq_update_save_title)" "$(i18n wsq_update_save_confirm)" || continue
                    WSQ_SAVE_KIND=legacy; WSQ_SELECTED_SAVE=""; return 0 ;;
                detect) wsq_select_save_candidate "$prefix" "$snapshot" && return 0 ;;
                browse) wsq_browse_save && return 0 ;;
                retry) wsq_retry_pending; return 1 ;;
                cancel) wsq_cancel_pending; return 1 ;;
            esac
        done
    fi
    if [ -z "$savedir$savefiles" ]; then
        wsq_select_save_candidate "$prefix" "$snapshot"
        return $?
    fi
    while true; do
        choice="$(menu_select "$(i18n wsq_update_save_title)" \
            "$(i18n wsq_update_save_prompt "$(wsq_display_path "SAVEDIR=$savedir  SAVEFILES=$savefiles")")" \
            keep "$(i18n wsq_update_save_keep)" \
            inspect "$(i18n wsq_inspect_title)" \
            detect "$(i18n wsq_update_save_detect)" \
            browse "$(i18n wsq_browser_title)" \
            retry "$(i18n wsq_no_save_retry)" \
            cancel "$(i18n wsq_launch_cancel)")" || return 1
        case "$choice" in
            keep)
                yesno_default_no "$(i18n wsq_update_save_title)" "$(i18n wsq_update_save_confirm)" || continue
                WSQ_SAVE_KIND=existing; WSQ_SELECTED_SAVE="$savedir"; return 0 ;;
            inspect)
                local normalized
                normalized="$(python3 - "$savedir" <<'PYCODE'
import sys
print(sys.argv[1].strip().strip('"').replace('\\', '/').rstrip('/') or '.')
PYCODE
)" || continue
                wsq_inspect_folder "$normalized" || true ;;
            detect) wsq_select_save_candidate "$prefix" "$snapshot" && return 0 ;;
            browse) wsq_browse_save && return 0 ;;
            retry) wsq_retry_pending; return 1 ;;
            cancel) wsq_cancel_pending; return 1 ;;
        esac
    done
}

wsq_resume_update() {
    # prefix/game_name/snapshot/exe_rel/runner are local to wsq_resume_build.
    local metadata phase save_rel save_kind test_save archive staged backup log original_name prepared_save
    local -a commit_args=()
    metadata="$(wsq_state_value metadata)"; phase="$(wsq_state_value phase)"; log="$(wsq_state_value update_log)"
    [ -s "$metadata" ] || { msgbox "$(i18n wsq_update_title)" "$(i18n wsq_pending_invalid)"; return; }
    archive="$(python3 "$WSQ_UPDATE_HELPER" value "$metadata" archive)" || return
    test_save="$(python3 "$WSQ_UPDATE_HELPER" value "$metadata" test_save)" || return
    original_name="$game_name"
    game_name="$(basename "$prefix" .wine).validated"
    prepared_save="$WSQ_SAVE_ROOT/$game_name"
    if [ "$(python3 "$WSQ_UPDATE_HELPER" value "$metadata" committed)" = True ]; then
        phase=committed
        wsq_update_state phase committed archive_backup "$(python3 "$WSQ_UPDATE_HELPER" value "$metadata" archive_backup)" || return
    fi
    if [ "$phase" != ready ] && [ "$phase" != committed ]; then
        wsq_update_review_save "$metadata" || return
        save_kind="$WSQ_SAVE_KIND"; save_rel="$WSQ_SELECTED_SAVE"
        case "$save_kind" in
            legacy)
                python3 "$WSQ_UPDATE_HELPER" stage-legacy "$metadata" >> "$log" 2>&1 || return
                python3 "$WSQ_UPDATE_HELPER" restore-legacy "$metadata" >> "$log" 2>&1 || return
                ;;
            existing)
                python3 "$WSQ_UPDATE_HELPER" stage-legacy "$metadata" >> "$log" 2>&1 || return
                # A test uses its own copy; never empty existing saves because
                # the new version failed to produce any data.
                if [ -d "$test_save" ] && find "$test_save" -mindepth 1 -print -quit | grep -q .; then
                    wsq_save_destination_prepare "$WSQ_SAVE_ROOT/$game_name" || return
                    python3 "$WSQ_UPDATE_HELPER" copy-test "$metadata" "$WSQ_SAVE_ROOT/$game_name" >> "$log" 2>&1 || return
                fi ;;
            registry)
                wsq_copy_registry_save || return
                python3 "$WSQ_UPDATE_HELPER" autorun "$prefix" "$exe_rel" --savedir . --savefiles user.reg >> "$log" 2>&1 || return ;;
            directory)
                yesno_default_no "$(i18n wsq_update_save_title)" \
                    "$(i18n wsq_save_confirm "$(wsq_display_path "$save_rel")" "$(wsq_display_path "$WSQ_SAVE_ROOT/$game_name")")" || return
                wsq_move_save_data "$prefix" "$save_rel" "$game_name" || return
                wsq_cleanup_internal_savedir "$prefix" "$save_rel" || return
                python3 "$WSQ_UPDATE_HELPER" autorun "$prefix" "$exe_rel" --savedir "${save_rel%/}/" >> "$log" 2>&1 || return ;;
            *) return ;;
        esac
        if [ "$save_kind" != legacy ]; then
        python3 "$WSQ_UPDATE_HELPER" restore-scripts "$metadata" >> "$log" 2>&1 || return
        python3 "$WSQ_UPDATE_HELPER" detach "$prefix" "$test_save" >> "$log" 2>&1 || {
            msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
        }
        if [ "$save_kind" = existing ]; then
            python3 "$WSQ_UPDATE_HELPER" restore-custom "$metadata" >> "$log" 2>&1 || return
        fi
        fi
        if [ -n "${WSQ_LAST_SAVE_BACKUP:-}" ]; then
            msgbox "$(i18n wsq_save_title)" "$(i18n wsq_save_backup_done "$WSQ_LAST_SAVE_BACKUP")"
        fi
        wsq_update_state phase ready || return
    fi
    if [ "$phase" != committed ]; then
    yesno_default_no "$(i18n wsq_update_title)" "$(i18n wsq_update_build_confirm "$(wsq_display_path "$archive")")" || return
    staged="$archive.update-tmp-$$"
    if ! maintenance_squash_wine "$prefix" "$staged"; then
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
    fi
    if ! wsq_update_run "$(i18n wsq_update_title)" "$(i18n wsq_update_validate)" "$log" \
        python3 "$WT_ROOT/helpers/wsquashfs_integrity.py" full "$staged" "$log" "$WSQ_STATE_DIR/update-cancel-$$"; then
        rm -f -- "$staged"
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
    fi
    [ ! -d "$prepared_save" ] || commit_args=(--prepared-save "$prepared_save")
    backup="$(python3 "$WSQ_UPDATE_HELPER" commit "$metadata" "$staged" "${commit_args[@]}" 2>> "$log")" || {
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_failed "$prefix" "$log")"; return
    }
    wsq_update_state phase committed archive_backup "$backup" || return
    else
        backup="$(wsq_state_value archive_backup)"
    fi
    python3 "$WSQ_UPDATE_HELPER" config "$WSQ_CONF" "$(basename "$prefix")" "$(basename "$archive")" \
        --backup-dir "$WSQ_STATE_DIR/config-backups" >> "$log" 2>&1 || {
        msgbox "$(i18n wsq_update_title)" "$(i18n wsq_runner_finalize_failed "$archive")"; return
    }
    local save_backup
    save_backup="$(python3 "$WSQ_UPDATE_HELPER" value "$metadata" save_backup)"
    [ -z "$save_backup" ] || msgbox "$(i18n wsq_save_title)" "$(i18n wsq_save_backup_done "$save_backup")"
    rm -f -- "$snapshot" "$WSQ_STATE_FILE" "$metadata" "$WSQ_STATE_DIR/wsq-launch-result"
    msgbox "$(i18n wsq_update_title)" "$(i18n wsq_update_done "$archive" "$backup" "$prefix" "$test_save")"
    if yesno_default_no "$(i18n squash_delete_source_title)" "$(i18n squash_delete_source_confirm "$(basename "$prefix")")"; then
        maintenance_delete_wine_dir_symlink_safe "$prefix" || true
    fi
    wsq_restart_emulationstation_deferred || true
    game_name="$original_name"
    wsq_post_build_menu
}
