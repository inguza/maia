#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

session_usage() {
    # TODO: Allow a more flexible placement of --use and other options
    cat <<'EOF'
USAGE

  maia session <command> [options]
  maia session

Manage sessions, including creation, switching, and metadata.

COMMANDS

  create <name> [--use|--nouse] [--workspace <ws>] [resolve-options] [--filesets <fs>[,fs2...]] [<src>]
    Create a new session (empty history & outbox) or copy from an existing session.

  list
    List all sessions (active one marked with *).

  set [<name>] [--use|--nouse] [--workspace <ws>] [resolve-options] [--filesets <fs>[,fs2...]]
    Set properties for a session.

  edit [<name>]
    Edit the session in an editor.

  use [<name>]
    Switch active session.
    When no <name> is given it displays the active session in use.

  select - an alias of use

  unuse
    No longer use any session.

  unselect - an alias of unuse

  show [options] [<name>]
    Show session metadata.
    Options are:
      --raw|--json  Output in json format

  content [<name>]
    Show the file content in this session.

  files [<name>]
    Show a list of files in this session.

  delete <name>
    Delete a session (cannot delete active).

OPTIONS

  --use (aliased as --select as well)
    Override configuration parameter auto_use_at_create or auto_use_at_set respectively
    so that the workspace is used after creation/set.

  --nouse (aliased as --unselect as well)
    Override configuration parameter auto_use_at_create or auto_use_at_set respectively
    so that the workspace is not used after creation/set.

  --workspace <name>
    Set workspace <name>. See note below.

  --filesets [fs1,[fs2...]]
     Set the active session filesets. See note below.
     The default is defined by config default_session_filesets.

  --extra-send-filesets [fs1,[fs2...]]
     Set the extra filesets to use when sending file content to the AI.
     These are not updated with file or change operations.
     The default is defined by config default_session_extra_send_filesets.

  --extra alias of --extra-send-filesets

  resolve-options:

  --resolve
     Same as --resolve-workspace --resolve-filesets

  --resolve-workspace
     Resolve __WORKSPACE_USED__ to the workspace in use. If no workspace is in use, the workspace default
     to __WORKSPACE_USED__.

  --resolve-filesets
     Resolve __WORKSPACE_FILESETS__ to the filesets of the workspace in use.

  --noresolve
     Same as --noresolve-workspace --noresolve-filesets

  --noresolve-workspace
     Do not resolve __WORKSPACE_USED__ to the workspace in use.

  --noresolve-filesets
     Do not resolve __WORKSPACE_FILESETS__ to the filesets of the workspace in use.

NOTES

  When <name> is optional it defaults to the active session.

  When no command is given it defaults to maia session use.

  A session is described as defunct if the directory exist, but the session metadata do not.
  Such sessions may contain history data and an outbox. Such sessions can be deleted and used
  only. The 'use' command is only to allow the user to extract histry and outbox.

  --workspace supports the special marker "__WORKSPACE_USED__" to
    represent the current workspace.

  --filesets supports the special marker "__WORKSPACE_FILESETS__" to
    represent all workspace filesets and "__SESSION_NAME__" to represent the name of the
    current session.

EOF
    exit 0
}

# parse_session_options [<args>…]
# Returns:
#   PARSED_WS          — string or empty
#   PARSED_FILESETS    — JSON array string (or empty)
# Leaves leftover flags in REMAINING_ARGS[@]
# parse_session_options [<args>…]
# Returns:
#   PARSED_WS          — string or empty
#   PARSED_FILESETS    — JSON array string (or empty)
# Leaves leftover flags in REMAINING_ARGS[@]
parse_session_options() {
    PARSED_WS=""
    PARSED_FILESETS=""
    PARSED_EXTRA_SEND_FILESETS=""
    REMAINING_ARGS=()
    # Do NOT initialize USE here; will be set before call

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)
                shift
                [[ -n "$1" ]] || { error "The option --workspace requires an argument."; session_usage; }
                PARSED_WS="$1"; shift
                ;;
            --filesets|--fileset)
                shift
		[[ $# -ge 1 ]] || { die "The option --filesets requires a comma-separated list."; }
		if [[ "$1" == "" ]]; then
		    PARSED_FILESETS="[]"
		else
                    IFS=',' read -r -a _arr <<< "$1"
                    local _jq=()
                    for fs in "${_arr[@]}"; do _jq+=( "\"$fs\"" ); done
		    PARSED_FILESETS="[$(printf '%s\n' "${_jq[@]}" | paste -sd "," -)]"
		fi
                shift
                ;;
	    --extra-send-filesets|--extra)
		local OPT="$1"
		shift
                [[ $# -ge 1 ]] || { die "The option $OPT requires a comma-separated list."; }
                if [[ "$1" == "" ]]; then
                    PARSED_EXTRA_SEND_FILESETS="[]"
                else
                    IFS=',' read -r -a _arr <<< "$1"
                    local _jq=()
                    for fs in "${_arr[@]}"; do _jq+=( "\"$fs\"" ); done
                    PARSED_EXTRA_SEND_FILESETS="[$(printf '%s\n' "${_jq[@]}" | paste -sd "," -)]"
                fi
                shift
		;;
	    --use|--select)
		shift
		USE="true"
		;;
	    --nouse|--unselect)
		shift
		USE="false"
		;;
            --resolve)
                RESOLVE_WORKSPACE=true
                RESOLVE_FILESETS=true
		shift
                ;;
            --resolve-workspace)
                RESOLVE_WORKSPACE=true
                shift
                ;;
            --resolve-filesets)
                RESOLVE_FILESETS=true
                shift
                ;;
            --noresolve)
                RESOLVE_WORKSPACE=false
                RESOLVE_FILESETS=false
		shift
                ;;
            --noresolve-workspace)
                RESOLVE_WORKSPACE=false
                shift
                ;;
            --noresolve-filesets)
                RESOLVE_FILESETS=false
                shift
                ;;
            -*)
                error "Unknown option '$1'" >&2
                session_usage
                ;;
            *)
                REMAINING_ARGS+=( "$1" )
                shift
                ;;
        esac
    done
}

handle_session_command() {
    [[ "$1" =~ ^-h|--help$ ]] && session_usage

    local cmd="$1"

    case "$cmd" in
	create)
	    shift
	    if [[ -z "$1" ]]; then
		die "Session name is required."
	    fi
	    local name="$1"
	    shift
	    local path="$(resolve_session_path "$name")"
	    if [[ -d "$path" ]] ; then
		die "Session '$name' already exists."
	    fi
	    local USE="$(jq -r '.auto_use_at_create' <<< "$_cfg")"
            # Parse options first to get workspace, filesets and extra_send_filesets
	    RESOLVE_WORKSPACE="$(jq -r '.auto_resolve_workspace' <<< "$_cfg")"
	    RESOLVE_FILESETS=false
            parse_session_options "$@"
	    # The remaining args after options may contain an optional source session name
	    local src_session=""
	    if [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; then
		src_session="${REMAINING_ARGS[0]}"
	    fi

	    local workspace="$(jq -r '.default_workspace' <<< "$_cfg")"
            if [[ "$workspace" == "__WORKSPACE_USED__" && "$RESOLVE_WORKSPACE" == "true" ]]; then
		local tws_name="$(resolve_workspace_name)"
		if [[ -n "$tws_name" ]] ; then
		    workspace="$tws_name"
		fi
            fi
	    local filesets_json="[]"
	    local extra_send_filesets_json="[]"
	    local src_ws
	    local src_fs
	    local src_extra_fs

	    # If copying from a source session, read its metadata first to get defaults
	    if [[ -n "$src_session" ]]; then
		local src_path="$(resolve_session_path "$src_session")"
		if [[ ! -d "$src_path" ]]; then
		    die "Source session '$src_session' does not exist."
		fi
		local src_meta="$(resolve_session_meta "$src_session")"
		if [[ -f "$src_meta" ]]; then
		    # Read workspace and filesets from source session
		    src_ws=$(jq -r '.workspace // empty' < "$src_meta")
		    src_fs=$(jq -c '.filesets // empty' < "$src_meta")
		    src_extra_fs=$(jq -c '.extra_send_filesets // []' < "$src_meta")

		    # Use source session workspace/filesets as defaults if not overridden by options
		    if [[ -z "$PARSED_WS" && -n "$src_ws" ]]; then
			workspace="$src_ws"
		    elif [[ -n "$PARSED_WS" ]]; then
			workspace="$PARSED_WS"
		    fi

		    if [[ -z "$PARSED_FILESETS" && "$src_fs" != "null" && "$src_fs" != "[]" ]]; then
			filesets_json="$src_fs"
		    elif [[ -n "$PARSED_FILESETS" ]]; then
			filesets_json="$PARSED_FILESETS"
		    fi

		    if [[ -z "$PARSED_EXTRA_SEND_FILESETS" && "$src_extra_fs" != "null" && "$src_extra_fs" != "[]" ]]; then
			extra_send_filesets_json="$src_extra_fs"
                    elif [[ -n "$PARSED_EXTRA_SEND_FILESETS" ]]; then
			extra_send_filesets_json="$PARSED_EXTRA_SEND_FILESETS"
                    fi
		else
		    # fallback if no metadata in source session
		    if [[ -n "$PARSED_WS" ]]; then
			workspace="$PARSED_WS"
		    fi
		    if [[ -n "$PARSED_FILESETS" ]]; then
			filesets_json="$PARSED_FILESETS"
		    fi
		    if [[ -n "$PARSED_EXTRA_SEND_FILESETS" ]]; then
			extra_send_filesets_json="$PARSED_EXTRA_SEND_FILESETS"
                    fi
		fi
	    else
		# No source session, use options or defaults
		if [[ -n "$PARSED_WS" ]] ; then
		    workspace="$PARSED_WS"
		fi
		if [[ -n "$PARSED_FILESETS" ]]; then
		    filesets_json="$PARSED_FILESETS"
		else
		    filesets_json=$(jq -r '.default_session_filesets' <<<"$_cfg")
		fi
		if [[ -n "$PARSED_EXTRA_SEND_FILESETS" ]]; then
                    extra_send_filesets_json="$PARSED_EXTRA_SEND_FILESETS"
		else
		    extra_send_filesets_json=$(jq -r '.default_session_extra_send_filesets' <<<"$_cfg")
		fi
	    fi

	    # Validate workspace exists
	    if [[ -n "$workspace" ]]; then
		validate_workspace_exists "$workspace"
	    fi

	    if [[ -n "$src_session" ]]; then
		# Copy session directory from src_session to new session directory, excluding logs
		mkdir -p "$path"
		# Copy all except logs directory
		shopt -s dotglob nullglob
		for item in "$src_path"/*; do
		    base_item="$(basename "$item")"
		    if [[ "$base_item" != "logs" ]]; then
			if [[ -d "$item" ]]; then
			    cp -a "$item" "$path/"
			else
			    cp "$item" "$path/"
			fi
		    fi
		done
		shopt -u dotglob nullglob

		# Update session metadata file with new workspace and filesets
		# If src_fs is exactly ["src_session"], then
		if [[ "$src_fs" == "[$(printf '"%s"' "$src_session")]" ]]; then
		    # Fileset file paths
		    local old_ws_dir=$(resolve_workspace_path "$src_ws")
		    local new_ws_dir=$(resolve_workspace_path "$workspace")
		    local old_fileset_file="$old_ws_dir/${src_session}.fileset"
		    local new_fileset_file="$new_ws_dir/${name}.fileset"
		    if [[ -f "$old_fileset_file" ]]; then
			cp "$old_fileset_file" "$new_fileset_file"
			info "Copied fileset content from '$old_fileset_file' to '$new_fileset_file'"
		    else
			# If no old fileset file, create empty new one
			: > "$new_fileset_file"
			info "Created empty fileset '$new_fileset_file'"
		    fi
		    filesets_json="[$(printf '"%s"' "$name")]"
		fi
		#
		update_session "$name" "false" "$workspace" "$filesets_json" "$extra_send_filesets_json"
		notice "Created session '$name' by copying from session '$src_session'"
	    else
		# Normal bootstrap new empty session
		mkdir -p "$path"
		update_session "$name" "true" "$workspace" "$filesets_json" "$extra_send_filesets_json"
		notice "Created session '$name'"
	    fi

            if [[ "$RESOLVE_FILESETS" == "true" ]]; then
                # Expand filesets markers (__WORKSPACE_FILESETS__, __SESSION_NAME__)
                local sess_name="$name"
                local ws_name="$ws"
                filesets_json=$(expand_filesets "$sess_name" "$ws_name" "$filesets_json")
		extra_send_filesets_json=$(expand_filesets "$sess_name" "$ws_name" "$extra_send_filesets_json")
            fi
	    # If filesets include __SESSION_NAME__, copy the old session fileset file to the new session fileset file
	    if [[ -n "$src_ws" && -n "$src_fs" && \
		      "$src_fs" == *"__SESSION_NAME__"* && \
		      "$filesets_json" == *"__SESSION_NAME__"* ]]; then
		local old_ws_dir=$(resolve_workspace_path "$src_ws")
		local new_ws_dir=$(resolve_workspace_path "$workspace")
		local old_fileset_file="$old_ws_dir/${src_session}.fileset"
		local new_fileset_file="$new_ws_dir/${name}.fileset"
		if [[ -f "$old_fileset_file" ]]; then
		    cp "$old_fileset_file" "$new_fileset_file"
		    info "Copied fileset content from '$old_fileset_file' to '$new_fileset_file'"
		fi
	    fi
	    # Ensure that any supplied session filesets exist in the workspace
	    local resworkspace="$(resolve_workspace_name "$workspace")"
	    if [[ -n "$resworkspace" ]]; then
		ensure_filesets_exists \
		    "$name" \
		    "$workspace" \
		    "$filesets_json"
		# Also ensure extra_send_filesets exist
		ensure_filesets_exists \
                    "$name" \
                    "$workspace" \
                    "$extra_send_filesets_json"
	    fi
	    if [[ "$USE" == "true" ]] ; then
		handle_x_use session "$name"
	    fi
	    ;;

	edit)
	    shift
            local name="$1"
	    ensure_session_exists "$name"
            handle_x_edit "session" "session" "$name" # Handles optional name
            ;;

        list|ls)
	    shift
	    ensure_session_exists "$(resolve_session_name)"
            handle_x_list session
            ;;

        use|select)
	    shift
            local name="$1"
            handle_x_use session "$name" # Handles optional name
            ;;

	unuse|unselect)
	    shift
            handle_x_unuse session
            ;;

        show)
	    shift
	    local raw_output=0
	    for arg in "$@"; do
		case "$arg" in
		    --raw|--json) shift; raw_output=1 ;;
		    *) break ; ;;
		esac
	    done
            # Show session.json
            local name="${1:-$(resolve_session_name)}"
	    ensure_session_exists "$name"
            local meta="$(resolve_session_meta "$name")"
            [[ -f "$meta" ]] || die "Session '${name:-$(resolve_session_name)}' does not exist"
	    local session_json=$(jq --arg name "$name" '. + {name: $name}' "$meta")
	    if (( raw_output )); then
		echo "$session_json" | jq .
	    else
		ws=$(jq -r '.workspace // empty' <<< "$session_json")
		local filesets_json=$(jq -r '.filesets // empty | @json' <<< "$session_json")
		local extra_send_filesets_json=$(jq -c '.extra_send_filesets // empty' <<< "$session_json")
		echo "Session:   $name"
		if [[ -n "$ws" ]]; then
		    local note=""
		    local ws_name="$ws"
                    if [[ "$ws" == "__WORKSPACE_USED__" ]]; then
			ws_name="$(resolve_workspace_name)"
			if [[ -z "$ws_name" ]] ; then
			    note=" (none in use)"
			else
			    note=" ($ws_name in use)"
			fi
                    fi
		    local ws_dir=$(resolve_workspace_path "$ws")
		    if [[ -z "$note" && ! -e "$ws_dir" ]] ; then
		       note=" ($ws_name missing)"
		    fi
		    local workspace_root="$(resolve_workspace_root "$ws_name")"
		    if [[ -z "$note" && ! -e "$workspace_root" ]] ; then
		       note=" (workspace root missing)"
		    fi
		    echo "Workspace: $ws$note"
		    local fileshow=false
		    if [[ "$filesets_json" != "" && "$filesets_json" != "[]" ]]; then
			echo "Filesets:"
			jq -r '.filesets[]' <<< "$session_json" | while IFS= read -r fs; do
			    local note=""
			    local fsname="$fs"
			    if [[ "$fs" == "__SESSION_NAME__" ]] ; then
				fsname=$name
			    fi
			    local file="$ws_dir/${fsname}.fileset"
			    if [[ ! -e "$file" ]] ; then
				note=" (missing)"
			    elif [[ ! -w "$file" ]] ; then
				note=" (ro)"
			    fi
			    echo "  - $fs$note"
			done
			fileshow=true
		    else
			echo "Filesets:  (none)"
		    fi
		    if [[ "$extra_send_filesets_json" != "" && "$extra_send_filesets_json" != "[]" ]]; then
			echo "Extra send filesets:"
			jq -r '.extra_send_filesets[]' <<< "$session_json" | while IFS= read -r fs; do
			    local note=""
			    local fsname="$fs"
			    if [[ "$fs" == "__SESSION_NAME__" ]] ; then
				fsname=$name
			    fi
			    local file="$ws_dir/${fsname}.fileset"
			    if [[ ! -e "$file" ]] ; then
				note=" (missing)"
			    elif [[ ! -w "$file" ]] ; then
				note=" (ro)"
			    fi
			    echo "  - $fs$note"
			done
			fileshow=true
		    else
			echo "Extra:     (none)"
		    fi
		    if [[ "$fileshow" == true ]] ; then
			echo -n "Files in "
			handle_session_command files "$name"
		    fi
		fi
	    fi
            ;;

	files|file)
	    shift
	    # Show session.json
            local name="${1:-$(resolve_session_name)}"
	    session_content_extract --list "$name"
	    ;;

        contents|content)
	    shift
            # Show session.json
            local name="${1:-$(resolve_session_name)}"
	    session_content_extract "$name"
            ;;

	set)
	    shift
	    local name_arg
	    # Optional name
	    if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
		name_arg="$1"; shift
	    else
		name_arg="$(resolve_session_name)"
	    fi
	    local name="$name_arg"
	    # Load current values
	    local meta="$(resolve_session_meta "$name")"
            [[ -f "$meta" ]] || die "Session '${name:-$(resolve_session_name)}' does not exist"
	    
	    local current_ws="$(jq -r '.workspace' < "$meta")"
	    local current_fs="$(jq -c '.filesets'  < "$meta")"
	    local current_extra_fs="$(jq -c '.extra_send_filesets // []' < "$meta")"
	    # Parse flags
	    local USE=$(jq -r '.auto_use_at_set' <<< "$_cfg")
	    RESOLVE_WORKSPACE="$(jq -r '.auto_resolve_workspace' <<< "$_cfg")"
	    RESOLVE_FILESETS=false
	    parse_session_options "$@"
	    # Fallback to current if flags omitted
	    local ws="${PARSED_WS:-$current_ws}"
            if [[ -n "$ws" ]]; then
		validate_workspace_exists "$ws"
            fi
	    local filesets_json="${PARSED_FILESETS:-$current_fs}"
	    local extra_send_filesets_json="${PARSED_EXTRA_SEND_FILESETS:-$current_extra_fs}"

            if [[ "$ws" == "__WORKSPACE_USED__" && "$RESOLVE_WORKSPACE" == "true" ]]; then
		local tws_name="$(resolve_workspace_name)"
		if [[ -n "$tws_name" ]] ; then
		    ws="$tws_name"
		fi
            fi

            if [[ "$RESOLVE_FILESETS" == "true" ]]; then
                # Expand filesets markers (__WORKSPACE_FILESETS__, __SESSION_NAME__)
                local sess_name="$name"
                local ws_name="$ws"
                filesets_json=$(expand_filesets "$sess_name" "$ws_name" "$filesets_json")
		extra_send_filesets_json=$(expand_filesets "$sess_name" "$ws_name" "$extra_send_filesets_json")
            fi

	    # Ensure that any supplied session filesets exist in the workspace
	    local resworkspace="$(resolve_workspace_name "$ws")"
	    if [[ -n "$resworkspace" ]]; then
		ensure_filesets_exists \
		    "$name" \
		    "$ws" \
		    "$filesets_json"
		ensure_filesets_exists \
                    "$name" \
		    "$ws" \
                    "$extra_send_filesets_json"
	    fi
	    update_session "$name" "false" "$ws" "$filesets_json" "$extra_send_filesets_json"
	    info "Updated session '$name' workspace='$ws' filesets=$filesets_json extra_send_filesets=$extra_send_filesets_json"
	    if [[ "$USE" == "true" ]] ; then
		handle_x_use --no-use-notice session "$name"
	    fi
	    ;;
	
	delete)
	    shift
            handle_x_delete session "$1" # Handles empty name
            ;;

	"")
	    handle_session_command use
	    ;;
        *)
            session_usage
            ;;
    esac
}
