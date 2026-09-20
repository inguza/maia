#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

file_usage() {
    cat <<'EOF'
USAGE

  maia file [options] <command>

Manage files in your workspace's filesets.

COMMANDS

  list|ls
    List all files in each fileset for the active session's workspace.

  content
    Show the content of the files.

  remember|add <path>[:filter] [...]
    Remember to include one or more files (relative to CWD) into the selected filesets.

  forget|delete <pattern> [...]
    Forget entries matching the given filename or glob from the selected
    filesets.

  discover
    Discover resources.

  verify
    Check the file entries for duplicates and whether the files still exist or not.

  clean
    Remove entries that do not match a local file (resources are kept) and also
    remove duplicated entries.

  cache-clear|clear-cache
    Clear resource cache, to re-read from the resource provider.

OPTIONS

  --all
    Operate on every .fileset under the session's workspace directory.

  --raw
    Print the file context without any space or workspace directory.

  --filesets fs1[,fs2]
    Comma-separated override of which workspace filesets to use.

  -h, --help
    Show this help message and exit.

EXAMPLES

    maia file list
      List files in the active session's workspace filesets.

    maia file remember src/*.js README.md
      Add specified files to the session's workspace filesets.

    maia file remember src/send.sh:send_usage src/count.sh:count_usage
      Add specified files with function filter to workspace active filesets.

    maia file forget *.tmp
      Forget entries matching local files *.tmp from workspace active filesets.

    maia file forget "*.tmp"
      Forget entries matching *.tmp from session's workspace filesets.

    maia file forget "*:*_usage"
      Forget all function filters ending with _usage in all files.

NOTES

  Paths are relative to the workspace root. Files outside the workspace is allowed
  if relative paths are used.

  Use globs carefully to avoid unintended matches.
  If you use globs (*) to match in the list and not local files, ensure you
  quote it.

EOF
    exit 0
}

realpath_or_readlink() {
    realpath -q "$1" || readlink -f "$1"
}

# Helper function to remove entries from filesets that exactly match given patterns
forget_entries() {
    local ws_root="$1"
    shift
    local patterns=("$@")
    # For file matching
    local i
    for i in "${!patterns[@]}"; do
	if [[ -n "${patterns[i]}" && "${patterns[i]}" != *[\*\?\[]* ]]; then
	    local relative_path
            if relative_path=$(realpath --relative-to="$ws_root" "${patterns[i]}" 2>/dev/null); then
		patterns[i]="$relative_path"
            fi
	fi
    done
    # For warning handling
    declare -A matched_patterns=()
    for fs in "${FILESET_FILES[@]}"; do
	if [[ ! -w "$fs" ]]; then
	    continue
	fi
        local tmp=$(mktemp)
        while IFS= read -r line || [[ -n "$line" ]]; do
	    line="${line%$'\r'}"
            local keep=true
            for pat in "${patterns[@]}"; do
		# A pattern must have # in it to remove a resource
		[[ "$pat" != *'#'* && "$line" == *'#'* ]] && continue
		if [[ "$pat" == *'|'* || "$pat" == *:* ]]; then
		    [[ "$line" == $pat ]] || continue
		else
		    line_file="${line%%[|:]*}"
		    [[ "$line_file" == $pat ]] || continue
		fi
                keep=false
		matched_patterns["$pat"]=true
                break
            done
            $keep && echo "$line" >> "$tmp"
        done < "$fs"
        mv "$tmp" "$fs"
        info "  Updated $(basename "$fs")"
    done

    # For warning handling
    local -a unmatched=()
    local pat
    for pat in "${patterns[@]}"; do
        if [[ ! -v matched_patterns["$pat"] ]]; then
            unmatched+=("$pat")
        fi
    done

    if [[ ${#unmatched[@]} -gt 0 ]]; then
        # Join unmatched patterns with ' and '
        local msg="${unmatched[0]}"
        local i
        for ((i=1; i<${#unmatched[@]}; i++)); do
            msg+=" and ${unmatched[i]}"
        done
        warn "$msg were not removed because they were not in the list in the first place."
    fi
}

find_filesets() {
    local ws_dir="$1"
    find "$ws_dir" -maxdepth 1 -name '*.fileset' -exec basename {} \; | sed 's/\.fileset$//'
}

handle_file_command() {
    # help flags
    [[ "$1" =~ ^-h|--help$ ]] && file_usage
    [[ "$2" =~ ^-h|--help$ ]] && file_usage

    # Determine active session and ensure it exists
    local session_name=$(resolve_session_name)
    ensure_session_exists "$session_name"

    # Resolve session workspace and validate it exists
    local session_ws=$(resolve_session_workspace "$session_name")
    validate_workspace_exists "$session_ws"

    # Resolve session expanded filesets JSON and parse into array
    local session_fs_json=$(get_session_expanded_filesets "$session_name")
    mapfile_from_json session_fs "$session_fs_json"
    local session_extra_send_fs_json=$(get_session_expanded_extra_send_filesets "$session_name")
    mapfile_from_json session_extra_send_fs "$session_extra_send_fs_json"

    # Parse global flags: --all and --filesets
    local all_flag=false
    local override_fs_csv=""
    local raw=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                all_flag=true
                shift
                ;;
            --raw)
                raw=true
                shift
                ;;
            --filesets)
                shift
                [[ -n "$1" ]] || die "Error: --filesets requires a comma-separated list"
                override_fs_csv="$1"
                shift
                ;;
            -h|--help)
                file_usage
                ;;
            *)
                break
                ;;
        esac
    done

    # Determine which filesets to operate on
    local -a active_fs=()
    if [[ -n "$override_fs_csv" ]]; then
        IFS=',' read -r -a active_fs <<< "$override_fs_csv"
    elif [[ "$all_flag" == true ]]; then
        # Use all filesets physically present in workspace dir
        local ws_dir=$(resolve_workspace_path "$session_ws")
        mapfile_from_command active_fs find_filesets "$ws_dir"
    else
        active_fs=("${session_fs[@]}")
    fi
    # Validate chosen filesets exist on disk
    local ws_dir=$(resolve_workspace_path "$session_ws")
    if [[ -z "$ws_dir" ]] ; then
	die "No workspace defined. File operations require a workspace."
    fi
    for fs in "${active_fs[@]}"; do
	ensure_file_exists "$ws_dir/${fs}.fileset"
    done

    # Build array of fileset files for operations
    local -a FILESET_FILES=()
    for fs in "${active_fs[@]}"; do
        FILESET_FILES+=( "$ws_dir/${fs}.fileset" )
    done
    [[ ${#FILESET_FILES[@]} -gt 0 ]] || die "No filesets found to operate on."

    local cmd="$1"

    case "$cmd" in
        list|ls)
            shift
            local workspace_root=$(resolve_workspace_root "$session_ws")
            if [[ ! -d "$workspace_root" ]]; then
                die "Workspace root '$workspace_root' does not exist."
            fi
            # Gather all unique files from filesets
            declare -A seen=()
            for fs in "${FILESET_FILES[@]}"; do
                while IFS= read -r line || [[ -n "$line" ]]; do
		    line="${line%$'\r'}"
                    [[ -z "$line" ]] && continue
                    seen["$line"]=1
                done < "$fs"
            done
	    if [[ "$raw" == false ]] ; then
		echo "$workspace_root:"
                printf '   %s\n' "${!seen[@]}"
	    else
                printf '%s\n' "${!seen[@]}"
	    fi
            ;;

	verify|clean)
            shift
            local workspace_root=$(resolve_workspace_root "$session_ws")
            if [[ ! -d "$workspace_root" ]]; then
                die "Workspace root '$workspace_root' does not exist."
            fi
            # Gather all unique files from filesets
	    local extra=""
	    if [[ "$cmd" == "clean" ]] ; then
		extra=", removing"
	    fi
            for fs in "${FILESET_FILES[@]}"; do
		declare -A seen=()
		declare tokeep=()
                while IFS= read -r line || [[ -n "$line" ]]; do
		    line="${line%$'\r'}"
                    [[ -z "$line" ]] && continue
		    # Resources are currently always kept.
		    if [[ "$line" == *"#"* ]]; then
			tokeep+=("$line")
			continue
		    fi
		    # Duplicate
		    if [[ -v seen["$line"] ]]; then
			notice "Duplicate file entry$extra: $line"
			continue
		    fi
		    local file_part filter_part actual_file
                    if [[ "$line" == *'|'* ]]; then
                        file_part="${line%%|*}"
                    else
                        file_part="$line"
                    fi
                    # Further split file_part on first colon ':' to get actual filename
                    actual_file="${file_part%%:*}"
		    # File no longer exists
		    if [[ ! -f "$workspace_root/$actual_file" ]]; then
			notice "File does not exist$extra: $line"
			continue
		    fi
		    tokeep+=("$line")
                done < "$fs"
		if [[ "$cmd" == "clean" ]] ; then
		    : > "$fs"
		    for line in "${tokeep[@]}" ; do
			printf '%s\n' "$line" >> "$fs"
		    done
		fi
            done
	    ;;

	clean)
	    ;;

	content)
	    shift
	    fileset_content_extract "content" "$session_ws" "${active_fs[@]}"
	    ;;

        add|remember)
            shift
            local workspace_root=$(resolve_workspace_root "$session_ws")
	    local serverscfg="$(get_config mcp_servers empty)"
	    mapfile_from_json servers "$serverscfg"
	    declare -A services
	    for server in "${servers[@]}" ; do
		local name="${server%%=*}"
		local endpoint="${server#*=}"
		services["$name"]="$endpoint"
	    done
            for path in "$@"; do
                local file_part filter_part
                if [[ "$path" == *'|'* ]]; then
                    file_part="${path%%|*}"
                    filter_part="${path#*|}"
                else
                    file_part="$path"
                    filter_part=""
                fi

		# Further split file_part on first colon ':' to get actual filename for existence check
                local actual_file="${file_part%%:*}"

		# Resolve absolute path of actual_file for existence check
                local abs
                if [[ "$actual_file" == /* ]]; then
                    abs=$(realpath_or_readlink "$actual_file")
                else
                    abs=$(realpath_or_readlink "$PWD/$actual_file")
                fi

                if [[ ! -f "$abs" ]]; then
		    local name="${file_part%%#*}"
		    local endpoint="${services[$name]}"
		    if [[ ! -n "$endpoint" ]] ; then
		        warn "File '$file_part' not found, skipping"
			continue
		    fi
                fi

		# Get relative path to workspace root for the whole original path (including filter parts)
                local rel_path=$(realpath --relative-to "$workspace_root" "$abs")

		# Rebuild relative path with colon filters and pipe filters (everything after actual_file)
                local remainder="${file_part#$actual_file}"
                if [[ -n "$remainder" ]]; then
                    rel_path+="$remainder"
                fi
                if [[ -n "$filter_part" ]]; then
                    rel_path+="|$filter_part"
                fi

                if [[ "$rel_path" == /* ]]; then
                    warn "Outside workspace root, skipping"
                    continue
                fi

                for fs in "${FILESET_FILES[@]}"; do
		    if [[ ! -w "$fs" ]]; then
			info "Read only fileset $fs, skipping update."
			continue
		    fi

		    add_file_to_fileset_file "$rel_path" "$fs"
                done
            done
            ;;

        delete|forget|remove|rm)
            shift
            local workspace_root=$(resolve_workspace_root "$session_ws")
            forget_entries "$workspace_root" "$@"
            ;;

	cache-clear|clear-cache)
	    local sessionpath="$(resolve_session_path)"
	    if [[ -d "$sessionpath" ]] ; then
		rm -Rf "$sessionpath/cache"
	    fi
	    ;;

	discover)
	    init_tool_search_dirs
	    local serverscfg="$(get_config mcp_servers empty)"
	    mapfile_from_json servers "$serverscfg"
	    for server in "${servers[@]}" ; do
		local name="${server%%=*}"
		local endpoint="${server#*=}"
		echo "[$name]"
		printf '%s\n' \
		       '{"jsonrpc":"2.0","id":2,"method":"resources/list","params":{}}' \
		    | mcp_request "discover" "$name" "$endpoint" |
		    jq -r --arg prefix "$name#" '
  .result.resources as $r |
  ($r | map(.name | length) | max) as $width |
  "  Name" + (" " * ($width - 4)) + "  Resource\n" +
  "  " + ("-" * $width) + "  " + ("-" * 40) + "\n" +
  ($r | map(
    "  \(.name | . + (" " * ($width - length)))  \($prefix)\(.uri)\n" +
    "  \((" " * $width))  \(.description // "")\(if .mimeType then " [\(.mimeType)]" else "" end)\n\n"
  ) | join(""))
'
	    done
	    ;;

        "")
            # Default to list
            handle_file_command list
            ;;
        *)
            die "Unknown file command: $cmd"
            ;;
    esac
}
