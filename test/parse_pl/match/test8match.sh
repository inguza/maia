    # Build FILESET_FILES array
    local FILESET_FILES
    if [[ "$all_flag" == true ]]; then
        mapfile -t FILESET_FILES < <(find "$ws_dir" -maxdepth 1 -name '*.fileset')
    else
        FILESET_FILES=()
        for fs in "${ACTIVE_FS[@]}"; do
            FILESET_FILES+=( "$ws_dir/${fs}.fileset" )
        done
    fi
    [[ ${#FILESET_FILES[@]} -gt 0 ]] || die "No filesets found to operate on."

    # Helper to remove entries from filesets
    forget_entries() {
        for fs in "${FILESET_FILES[@]}"; do
            local tmp="$(mktemp)"
            while IFS= read -r line; do
                local keep=true
                for pat in "$@"; do
                    [[ "$line" == $pat ]] && keep=false && break
                done
                $keep && echo "$line" >> "$tmp"
            done < "$fs"
            mv "$tmp" "$fs"
	    info "  Updated $(basename "$fs")"
        done
    }

    local cmd="$1"
    case "$cmd" in
        list|ls)
	    shift
