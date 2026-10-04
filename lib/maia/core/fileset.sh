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

declare -A in_ws=()
declare -A in_sess=()
declare -A in_sess_e_s=()
fileset_marker() {
    name="$1"
    if [[ -v in_ws["$name"] ]] ; then
	echo -n "*"
    fi
    if [[ -v in_sess["$name"] ]]; then
	echo -n "+"
    fi
    if [[ -v in_sess_e_s["$name"] ]]; then
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
	    local wfs="$(resolve_workspace_filesets)"
            read -ra WS_FSS <<< "$wfs"
            # load session filesets
	    local efs="$(get_session_expanded_filesets "$session")"
	    read -ra SESS_FSS <<< "$efs"
	    local esfs="$(get_session_expanded_extra_send_filesets "$session")"
	    read -ra SESS_E_S_FSS <<< "$esfs"
            # build quick-lookup maps
	    local fs
            for fs in "${WS_FSS[@]}" ; do
		[[ -n "$fs" ]] || continue
		in_ws["$fs"]=1
	    done
            for fs in "${SESS_FSS[@]}" ; do
		[[ -n "$fs" ]] || continue
		in_sess["$fs"]=1
	    done
            for fs in "${SESS_E_S_FSS[@]}" ; do
		[[ -n "$fs" ]] || continue
		in_sess_e_s["$fs"]=1
	    done
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
            # load workspace filesets
	    local wfs="$(resolve_workspace_filesets)"
            read -ra WS_FSS <<< "$wfs"
            # load session filesets
	    local efs="$(get_session_expanded_filesets "$session")"
	    read -ra SESS_FSS <<< "$efs"
	    local esfs="$(get_session_expanded_extra_send_filesets "$session")"
	    read -ra SESS_E_S_FSS <<< "$esfs"
            # Build lookup maps
	    local fs
            for fs in "${WS_FSS[@]}"; do
		[[ -n "$fs" ]] || continue
		in_ws["$fs"]=1
	    done
            for fs in "${SESS_FSS[@]}"; do
		[[ -n "$fs" ]] || continue
		in_sess["$fs"]=1
	    done
            for fs in "${SESS_E_S_FSS[@]}"; do
		[[ -n "$fs" ]] || continue
		in_sess_e_s["$fs"]=1
	    done
            # Determine which filesets to show
            local to_show=()
            if [[ "$show_all" == true ]]; then
		mapfile_from_command to_show resolve_all_workspace_filesets
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
                    while IFS= read -r line || [[ -n "$line" ]]; do
			line="${line%$'\r'}"
			printf '     %s\n' "$line"
                    done < "$file"
		else
		    warn "Fileset $name does not exist."
		fi
            done
            ;;

	clear)
	    shift
            if [[ -z "$1" ]]; then
		# no name: clear all filesets in use from session expanded filesets
		mapfile_from_command names get_session_expanded_filesets "$session"
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
		mapfile_from_command names get_session_expanded_filesets "$session"
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
