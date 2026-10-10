#!/bin/bash

STARTER_DATA="$WT_ROOT/data/starter-pack.json"
RUNNERS_DATA="$WT_ROOT/data/runners.json"
STARTER_STAGE="$WT_HOME/staging/starter-pack"

starter_status_tsv() {
    python3 - "$STARTER_DATA" "$RUNNERS_DATA" "$WT_ROOT/helpers" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[3])
from runner_names import canonical
starter=json.load(open(sys.argv[1], encoding="utf-8"))
catalog=json.load(open(sys.argv[2], encoding="utf-8"))
byid={r["id"]:r for r in catalog["runners"]}
install_path=catalog.get("install_path","/userdata/system/wine/custom")

print("META\t"+starter["version"]+"\t"+install_path)
for rid in starter["classic_runner_ids"]:
    r=byid[rid]
    target=os.path.join(install_path, canonical(r["name"]))
    legacy_target=os.path.join(install_path, r.get("legacy_id", r["id"]))
    state="installed" if os.path.isdir(target) or os.path.isdir(legacy_target) else "missing"
    print("CLASSIC\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % (
        rid, canonical(r["name"]), state, r["file"], r["size_bytes"], r["download_url"], r["sha256"]
    ))
for rid in starter.get("umu_runner_ids", []):
    target=os.path.join(install_path, canonical(rid))
    state="installed" if os.path.isdir(target) else "missing"
    print("UMU\t%s\t%s" % (rid, state))
PY
}

starter_summary_values() {
    starter_status_tsv | python3 -c '
import sys
classic=ci=cm=umu=ui=um=download=0
version=path=""
for raw in sys.stdin:
    p=raw.rstrip("\n").split("\t")
    if p[0]=="META":
        version,path=p[1],p[2]
    elif p[0]=="CLASSIC":
        classic+=1
        if p[3]=="installed": ci+=1
        else:
            cm+=1
            download+=int(p[5])
    elif p[0]=="UMU":
        umu+=1
        if p[2]=="installed": ui+=1
        else: um+=1
print("\t".join(map(str,[version,path,classic,ci,cm,umu,ui,um,download])))
'
}

install_classic_runner_row() {
    local name="$1" file="$2" url="$3" sha="$4" target="$BATOCERA_CUSTOM_WINE/$name"
    local stage archive extract candidate count
    [ -d "$target" ] && return 0

    stage="$(mktemp -d "$STARTER_STAGE/${name}.XXXXXX")" || return 1
    archive="$stage/$file"
    extract="$stage/extracted"
    mkdir -p "$extract"

    echo
    echo "$(i18n starter_installing_classic "$name")"
    echo "$(i18n starter_downloading "$file")"
    if ! download_file "$url" "$archive"; then
        echo "$(i18n starter_failed_download "$name")" >&2
        rm -rf "$stage"
        return 1
    fi

    echo "$(i18n starter_checksum)"
    if ! verify_sha256 "$archive" "$sha"; then
        echo "$(i18n starter_checksum_bad "$name")" >&2
        rm -rf "$stage"
        return 1
    fi
    echo "$(i18n starter_checksum_ok)"

    echo "$(i18n starter_extracting "$name")"
    if ! tar -xJf "$archive" -C "$extract"; then
        echo "$(i18n starter_failed_extract "$name")" >&2
        rm -rf "$stage"
        return 1
    fi

    if [ -d "$extract/$name" ]; then
        candidate="$extract/$name"
    else
        count="$(find "$extract" -mindepth 1 -maxdepth 1 -type d | wc -l)"
        [ "$count" -eq 1 ] || {
            echo "$(i18n starter_bad_archive "$name")" >&2
            rm -rf "$stage"
            return 1
        }
        candidate="$(find "$extract" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    fi

    [ ! -e "$target" ] || {
        echo "$(i18n starter_target_exists "$target")" >&2
        rm -rf "$stage"
        return 1
    }

    mv "$candidate" "$target" || {
        rm -rf "$stage"
        return 1
    }

    rm -rf "$stage"
    echo "$(i18n starter_installed "$name")"
}

install_starter_tokens() {
    local selected="$1" failures=0 selected_classic_download=0
    local kind id name state file size url sha token
    local need_umu=0 selected_count=0 umu_selected_count=0 umu_mode="" free estimate

    [ -n "$selected" ] || return 0

    while IFS= read -r token; do
        [ -n "$token" ] || continue
        selected_count=$((selected_count+1))
        case "$token" in
            CLASSIC:*)
                id="${token#CLASSIC:}"
                while IFS=$'\t' read -r kind row_id name state file size url sha; do
                    [ "$kind" = "CLASSIC" ] || continue
                    [ "$row_id" = "$id" ] || continue
                    [ "$state" = "missing" ] || break
                    selected_classic_download=$((selected_classic_download + size))
                    break
                done <<< "$(starter_status_tsv)"
                ;;
            UMU:*) need_umu=1; umu_selected_count=$((umu_selected_count+1)) ;;
        esac
    done <<< "$selected"

    [ "$selected_count" -gt 0 ] || return 0
    [ "$umu_selected_count" -le 1 ] || umu_mode=batch

    estimate=$(( selected_classic_download * 4 + 536870912 ))
    free="$(free_bytes_userdata)"
    if [ -n "$free" ] && [ "$free" -lt "$estimate" ]; then
        msgbox "$(i18n starter_title)" \
            "$(i18n starter_space_low "$(human_bytes "$estimate")" "$(human_bytes "$free")")"
        return 1
    fi

    mkdir -p "$STARTER_STAGE" "$BATOCERA_CUSTOM_WINE"

    if [ "$need_umu" -eq 1 ]; then
        echo
        echo "$(i18n starter_preparing_umu)"
        ensure_umu_toolbox || failures=$((failures+1))
    fi

    while IFS= read -r token; do
        [ -n "$token" ] || continue
        case "$token" in
            CLASSIC:*)
                id="${token#CLASSIC:}"
                while IFS=$'\t' read -r kind row_id name state file size url sha; do
                    [ "$kind" = "CLASSIC" ] || continue
                    [ "$row_id" = "$id" ] || continue
                    [ "$state" = "missing" ] || break
                    install_classic_runner_row "$name" "$file" "$url" "$sha" || failures=$((failures+1))
                    break
                done <<< "$(starter_status_tsv)"
                ;;
            UMU:*)
                id="${token#UMU:}"
                if [ "$need_umu" -eq 1 ] && umu_toolbox_installed; then
                    install_umu_runner "$id" "$umu_mode" || {
                        echo "$(i18n umu_runner_failed "$id")" >&2
                        failures=$((failures+1))
                    }
                fi
                ;;
        esac
    done <<< "$selected"

    if [ "$failures" -eq 0 ]; then
        msgbox "$(i18n starter_title)" "$(i18n starter_selected_complete)"
    else
        msgbox "$(i18n starter_title)" "$(i18n starter_partial)"
    fi
}

install_starter_pack() {
    local vals version install_path classic ci cm umu ui um download free estimate
    local selected=""

    vals="$(starter_summary_values)" || {
        msgbox "$(i18n starter_title)" "$(i18n starter_missing_catalog)"
        return
    }
    IFS=$'\t' read -r version install_path classic ci cm umu ui um download <<< "$vals"

    if [ "$cm" -eq 0 ] && [ "$um" -eq 0 ]; then
        msgbox "$(i18n starter_title)" "$(i18n starter_nothing)"
        return
    fi

    free="$(free_bytes_userdata)"
    estimate=$(( download * 4 + um * 2147483648 + 536870912 ))

    yesno "$(i18n starter_title)" \
        "$(i18n starter_full_warning "$(human_bytes "$estimate")" "$(human_bytes "${free:-0}")")" || return

    while IFS=$'\t' read -r kind id name state file size url sha; do
        case "$kind" in
            CLASSIC)
                [ "$state" = "missing" ] && selected+="CLASSIC:$id"$'\n'
                ;;
            UMU)
                [ "$name" = "missing" ] && selected+="UMU:$id"$'\n'
                ;;
        esac
    done <<< "$(starter_status_tsv)"

    install_starter_tokens "$selected"
}

install_selected_starter_runners() {
    local -a items=()
    local kind id name state file size url sha
    local missing=0 selected="" label

    while IFS=$'\t' read -r kind id name state file size url sha; do
        case "$kind" in
            CLASSIC)
                [ "$state" = "missing" ] || continue
                missing=$((missing+1))
                label="$(i18n starter_classic_item "$name" "$(human_bytes "$size")")"
                items+=("CLASSIC:$id" "$label" "off")
                ;;
            UMU)
                [ "$name" = "missing" ] || continue
                missing=$((missing+1))
                label="$(i18n starter_umu_item "$id")"
                items+=("UMU:$id" "$label" "off")
                ;;
        esac
    done <<< "$(starter_status_tsv)"

    if [ "$missing" -eq 0 ]; then
        msgbox "$(i18n starter_title)" "$(i18n starter_nothing)"
        return
    fi

    selected="$(checklist_select "$(i18n starter_select_title)" \
        "$(i18n starter_select_prompt)" "${items[@]}")" || return

    if [ -z "$selected" ]; then
        msgbox "$(i18n starter_title)" "$(i18n starter_select_none)"
        return
    fi

    yesno "$(i18n starter_title)" "$(i18n starter_select_confirm)" || return
    install_starter_tokens "$selected"
}

starter_view_runners() {
    local rows report kind id name state file size url sha label
    rows="$(starter_status_tsv)" || {
        msgbox "$(i18n starter_title)" "$(i18n starter_missing_catalog)"
        return 1
    }
    report="$(mktemp /tmp/wt-starter-list.XXXXXX)" || return 1
    while IFS=$'\t' read -r kind id name state file size url sha; do
        case "$kind" in
            META) printf '%s\n\n' "$(i18n starter_list_header "$id" "$name")" ;;
            CLASSIC|UMU)
                if [ "$kind" = UMU ]; then
                    state="$name"
                    name="$id"
                    label=UMU
                else
                    label="$(i18n starter_list_classic)"
                fi
                printf '%s | %s | %s\n' "$label" "$name" "$(i18n "starter_list_$state")"
                ;;
        esac
    done <<< "$rows" > "$report"
    if have_dialog; then
        wt_clear_tty
        dialog --clear --no-shadow --exit-label "$(i18n back)" \
            --title "$(i18n starter_list_title)" --textbox "$report" 24 100
        wt_clear_tty
    else
        cat "$report"
        read -r -p "$(i18n press_enter)" _
    fi
    rm -f "$report"
} >&2

starter_pack_menu() {
    while true; do
        local vals version install_path classic ci cm umu ui um download free estimate choice summary
        vals="$(starter_summary_values 2>/dev/null)" || {
            msgbox "$(i18n starter_title)" "$(i18n starter_missing_catalog)"
            return
        }
        IFS=$'\t' read -r version install_path classic ci cm umu ui um download <<< "$vals"
        free="$(free_bytes_userdata)"
        estimate=$(( download * 4 + um * 2147483648 + 536870912 ))
        summary="$(i18n starter_summary \
            "$version" "$classic" "$ci" "$cm" \
            "$umu" "$ui" "$um" \
            "$(human_bytes "$estimate")" \
            "$(human_bytes "${free:-0}")")"

        choice="$(menu_select "$(i18n starter_title)" "$(i18n starter_intro)\n\n$summary" \
            "1" "$(i18n starter_install_all)" \
            "2" "$(i18n starter_install_select)" \
            "3" "$(i18n starter_list_title)" \
            "0" "$(i18n back)")" || return

        case "$choice" in
            1) install_starter_pack ;;
            2) install_selected_starter_runners ;;
            3) starter_view_runners ;;
            0|"") return ;;
        esac
    done
}
