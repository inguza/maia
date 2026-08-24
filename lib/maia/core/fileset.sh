#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

fileset_usage() {
    cat <<'EOF'
USAGE

  maia fileset <command> [options]
  maia fileset

Manage filesets within the active workspace.

COMMANDS

  list|ls
    List all filesets in the active workspace.

  create <name> [<src>]
    Create a new fileset named <name>, optionally copying from <src>.

  use [<name>[,<name2>...]]
    Make <name>(s) the fileset(s) for the current workspace or session.
    If no name is provided print the fileset(s) currently in use.
    The workspace use is updated if the session filesets is defined
    as __WORKSPACE_FILESETS__. If not the session filesets list is updated.

  select - an alias of use

  show [<name>] [--all] [--workspace]
    Show entries in <name> (glob patterns), optional slice “n-m”.
    If name is omitted session active filesets are shown unless
    any of the below options are used.
    --all show all filesets
    --workspace show workspace active filesets

  clear [<name>]
    Delete all patterns from <name>.
    If name is omitted, it clears all current files sets.

  delete [<name>]
    Delete the fileset <name>.
    If name is omitted, it deletes all current files sets.

  readonly [<name>]
    Make <name> read-only, meaning the entries cannot be modified. Note that the
    content that the entries represent are not read-only. Only the list.

  readwrite [<name>}
    Make <name> read-write.

OPTIONS

  -h, --help
    Show this help message.

EXAMPLES

    maia fileset list
      List all filesets in the current workspace.

    maia fileset create myfileset
      Create a new fileset named "myfileset".

    maia fileset use myfileset,default
      Use "myfileset" and "default" as active filesets.

NOTES

  Filesets are collections of file patterns used to manage project files.

  For fileset list and fileset show:
  '*' the fileset is in the workspace fileset list currently in use.
  '+' the fileset is in the session fileset list currently in use.

EOF
    exit 0
}

declare -A in_ws in_sess in_sess_e_s
fileset_marker() {
    name="$1"
    if [[ ${in_ws[$name]} ]] ; then
	echo -n "*"
    fi
    if [[ ${in_sess[$name]} ]]; then
	echo -n "+"
    fi
    if [[ ${in_sess_e_s[$name]} ]]; then
	echo -n "^"
    fi
}

fileset_note() {
    local f="$1"
    if [[ ! -e "$f" ]] ; then
	echo -n " (missing)"
    elif [[ ! -w "$f" ]] ; then
	echo -n " (ro)"
    fi
}

handle_fileset_command() {
    [[ "$1" =~ ^-h|--help$ ]] && fileset_usage

    # Base directory for this workspace
    local ws_path="$(resolve_workspace_path)"
    local ws_name="$(resolve_workspace_name)"
    local ws_root="$(resolve_workspace_root)"
    if [[ -z "$ws_name" ]] ; then
	die "No workspace in use. Create a workspace and set it to be used by the session."
    fi
    if [[ ! -d "$ws_root" ]] ; then
	die "Workspace $ws_root does not exist."
    fi

    # Helper to get the .fileset path
    fileset_file() { printf '%s/%s.fileset' "$ws_path" "$1"; }

    # For use in several subcommands below
    local session=$(resolve_session_name)

    local cmd="$1"
    case "$cmd" in
	readonly|ro)
	    shift
	    if [[ -z "$1" ]]; then
                die "Missing fileset name for readonly command."
            fi
            local fs="$1"
            local fs_file=$(fileset_file "$fs")
            ensure_file_exists "$fs_file"
            # Mark as read-only by setting filesystem permissions
            chmod a-w "$fs_file"
            info "Fileset '$fs' marked as read-only."
            ;;
    
        readwrite|rw)
	    shift
	    if [[ -z "$1" ]]; then
                die "Missing fileset name for readwrite command."
            fi
            local fs="$1"
            local fs_file=$(fileset_file "$fs")
            ensure_file_exists "$fs_file"
            # Remove read-only flag by restoring user write permission
            chmod u+w "$fs_file"
            info "Fileset '$fs' marked as read-write."
            ;;
	    
	list|ls)
	    shift
            # load workspace filesets
            mapfile -t WS_FSS < <(resolve_workspace_filesets)
            # load session filesets
	    local expanded_filesets=$(get_session_expanded_filesets "$session")
	    local expanded_extra_send_filesets=$(get_session_expanded_extra_send_filesets "$session")
	    mapfile -t SESS_FSS < <(jq -r '.[]' <<<"$expanded_filesets")
	    mapfile -t SESS_E_S_FSS < <(jq -r '.[]' <<<"$expanded_extra_send_filesets")
            # build quick-lookup maps
	    local fs
            for fs in "${WS_FSS[@]}";   do in_ws["$fs"]=1;   done
            for fs in "${SESS_FSS[@]}"; do in_sess["$fs"]=1; done
            for fs in "${SESS_E_S_FSS[@]}"; do in_sess_e_s["$fs"]=1; done
            # iterate over every .fileset on disk
            local ws_dir="$(resolve_workspace_path)"
            for f in "$ws_dir"/*.fileset; do
		[[ -f "$f" ]] || continue
		local name="${f##*/}"; name="${name%.fileset}"
		local note=$(fileset_note "$f")
		local marker=$(fileset_marker "$name")
		printf '%-3s %s%s\n' "$marker" "$name" "$note"
            done
            ;;

        create)
	    shift
            [[ -n "$1" ]] || { echo "name required." >&2; fileset_usage; }
            local name="$1";   shift
            local dest="$(fileset_file "$name")"
            [[ ! -e "$dest" ]] || die "Fileset '$name' already exists."
            if [[ -n "$1" ]]; then
                local srcf="$(fileset_file "$1")"
                [[ -f "$srcf" ]] || die "Source fileset '$1' not found."
                cp "$srcf" "$dest"
            else
                : > "$dest"
            fi
            info "Created fileset '$name'"
            ;;

	show)
	    shift
            local show_all=false
            local show_workspace=false
            if [[ "$1" == "--all" ]]; then
		show_all=true
		shift
	    elif [[ "$1" == "--workspace" ]]; then
		show_workspace=true
		shift
            fi
            # Load workspace and session lists
            mapfile -t WS_FSS < <(resolve_workspace_filesets)
	    local expanded_filesets=$(get_session_expanded_filesets "$session")
	    mapfile -t SESS_FSS < <(jq -r '.[]' <<<"$expanded_filesets")
	    local expanded_extra_send_filesets=$(get_session_expanded_extra_send_filesets "$session")
	    mapfile -t SESS_E_S_FSS < <(jq -r '.[]' <<<"$expanded_extra_send_filesets")
            # Build lookup maps
	    local fs
            for fs in "${WS_FSS[@]}";   do in_ws["$fs"]=1;   done
            for fs in "${SESS_FSS[@]}"; do in_sess["$fs"]=1; done
            for fs in "${SESS_E_S_FSS[@]}"; do in_sess_e_s["$fs"]=1; done
            # Determine which filesets to show
            local to_show=()
            if [[ "$show_all" == true ]]; then
		mapfile -t to_show < <(resolve_all_workspace_filesets)
	    elif [[ "$show_workspace" == true ]]; then
		to_show=( "${WS_FSS[@]}" )
	    elif [[ -n "$1" ]]; then
		to_show=( "$1" )
            else
		to_show=( "${SESS_FSS[@]}" "${SESS_E_S_FSS[@]}" )
            fi
	    echo "$ws_root:"
            for name in "${to_show[@]}"; do
		local file="$(resolve_workspace_path)/${name}.fileset"
		if [[ -f "$file" ]]; then
		    local note=$(fileset_note "$file")
		    local marker=$(fileset_marker "$name")
		    printf '%-3s %s%s\n' "$marker" "$name" "$note"
		    # print its contents if file exists
                    while IFS= read -r line; do
			printf '     %s\n' "$line"
                    done < "$file"
		else
		    warn "Fileset $name does not exist."
		fi
            done
            ;;

	use|select)
	    shift
            if [[ -z "$1" ]] ; then
                # Show current filesets in use, prefer session filesets if session overrides
		local sess_meta=$(resolve_session_meta "$session")
		if [[ -f "$sess_meta" ]]; then
		    local sess_filesets=$(jq -r '.filesets' "$sess_meta")
		    if [[ -n "$sess_filesets" ]]; then
			# Expand __SESSION_NAME__ marker in session filesets before printing
			local expanded=$(expand_filesets "$session" "$(resolve_session_workspace "$session")" "$sess_filesets")
			# Output as CSV
			jq -r 'join(",")' <<< "$expanded"
			exit 0
		    fi
		fi
		resolve_workspace_filesets | paste -sd "," -
		exit 0
	    fi
            local csv="$1"
	    # Split CSV into array
            IFS=',' read -r -a new_lst <<< "$csv"
	    # Validate each exists on disk
            local ws_dir="$(resolve_workspace_path)"
            for fs in "${new_lst[@]}"; do
		if [[ ! -f "$ws_dir/${fs}.fileset" ]]; then
                    die "Fileset '$fs' does not exist."
		fi
            done

            # Detect if session metadata uses __WORKSPACE_FILESETS__ marker in default_session_filesets
            local session=$(resolve_session_name)
            local sess_meta=$(resolve_session_meta "$session")
            local sess_filesets_raw=""
            if [[ -f "$sess_meta" ]]; then
                sess_filesets_raw=$(jq -c '.filesets' "$sess_meta" 2>/dev/null || echo "")
            fi
            local uses_workspace_marker=false
            if [[ -n "$sess_filesets_raw" ]]; then
                uses_workspace_marker=$(jq --arg marker "__WORKSPACE_FILESETS__" 'index($marker) != null' <<<"$sess_filesets_raw")
            fi

            local jq_arr=()
            for fs in "${new_lst[@]}"; do
                jq_arr+=( "\"$fs\"" )
            done
	    local IFSS="$IFS"
	    local IFS=","
            local filesets_json="[${jq_arr[*]}]"
	    # Must restore IFS or else everything will start to break
	    IFS="$IFSS"
            if [[ "$uses_workspace_marker" == "true" || ! -e "$sess_meta" ]]; then
                # Update workspace metadata filesets
                local current_path="$(resolve_workspace_root)"
                write_workspace_meta \
                    "$(resolve_workspace_path)" \
                    "$current_path" \
                    "$filesets_json"
                notice "Workspace filesets updated: $filesets_json"
            else
                # Update session metadata filesets
		local ws_name=$(jq -r '.workspace // empty' < "$sess_meta")
		if [ -z "$ws_name" ] ; then
		    die "Must have a workspace name"
		fi
		update_session "$session" "false" "$ws_name" "$filesets_json"
                notice "Session filesets updated: $filesets_json"
            fi
            ;;

	clear)
	    shift
            if [[ -z "$1" ]]; then
		# no name: clear all filesets in use from session expanded filesets
		local expanded_filesets=$(get_session_expanded_filesets "$session")
		mapfile -t names < <(jq -r '.[]' <<<"$expanded_filesets")
		for name in "${names[@]}"; do
		    : > "$(fileset_file "${name}")"
		    info "Cleared fileset '$name'"
		done
	    else
		local name="$1"
		# clear specific fileset
		: > "$(fileset_file "${name}")"
		info "Cleared fileset '$name'"
	    fi
            ;;

	delete)
	    shift
            if [[ -z "$1" ]]; then
		# no name: clear all filesets in use from session expanded filesets
		local expanded_filesets=$(get_session_expanded_filesets "$session")
		mapfile -t names < <(jq -r '.[]' <<<"$expanded_filesets")
		for name in "${names[@]}"; do
		    rm -f "$(fileset_file "$name")"
		    info "Deleted fileset '$name'"
		done
	    else
		local name="$1"
		# clear specific fileset
		rm -f "$(fileset_file "$name")"
		info "Deleted fileset '$name'"
	    fi
            ;;

	"")
	    handle_fileset_command show
	    ;;
        *)
	    shift
	    error "Unknown command '$cmd'"
            fileset_usage
            ;;
    esac
}
