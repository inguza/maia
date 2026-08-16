#
# Copyright (c) 2025 Ola Lundqvist <ola@inguza.com>
#
session_usage() {
    # TODO: Allow a more flexible placement of --use and other options
    cat <<'EOF'
USAGE

  aia session <command> [options]
  aia session

Manage sessions, including creation, switching, and metadata.

COMMANDS

  create <name> [--use|--nouse] [--workspace <ws>] [--filesets <fs>[,fs2...]] [<src>]
    Create a new session (empty history & outbox) or copy from an existing session.

  list
    List all sessions (active one marked with *).

  set [<name>] [--use|--nouse] [--workspace <ws>] [--filesets <fs>[,fs2...]]
    Set properties for a session.

  edit [<name>] [--use|--nouse]
    Edit the session in an editor.

  use [<name>]
    Switch active session.
    When no <name> is given it displays the active session in use.

  unuse
    No longer use any session.

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

  --use
    Override configuration parameter auto_use_at_create or auto_use_at_set respectively
    so that the workspace is used after creation/set.

  --nouse
    Override configuration parameter auto_use_at_create or auto_use_at_set respectively
    so that the workspace is not used after creation/set.

  --workspace supports the special marker "__WORKSPACE_USED__" to
    represent the current workspace.

  --filesets supports the special marker "__WORKSPACE_FILESETS__" to
    represent all workspace filesets and "__SESSION_NAME__" to represent the name of the
    current session.

NOTES

  When <name> is optional it defaults to the active session.

  When no command is given it defaults to aia session use.

  A session is described as defunct if the directory exist, but the session metadata do not.
  Such sessions may contain history data and an outbox. Such sessions can be deleted and used
  only. The 'use' command is only to allow the user to extract histry and outbox.

EOF
    exit 0
}

# parse_session_options [<args>…]
# Returns:
#   PARSED_WS          — string or empty
#   PARSED_FILESETS    — JSON array string (or empty)
# Leaves leftover flags in REMAINING_ARGS[@]
parse_session_options() {
    PARSED_WS=""
    PARSED_FILESETS=""
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
                [[ -n "$1" ]] || { die "The option --filesets requires a comma-separated list."; }
                IFS=',' read -r -a _arr <<< "$1"
                local _jq=()
                for fs in "${_arr[@]}"; do _jq+=( "\"$fs\"" ); done
		PARSED_FILESETS="[$(printf '%s\n' "${_jq[@]}" | paste -sd "," -)]"
                shift
                ;;
	    --use)
		shift
		USE="true"
		;;
	    --nouse)
		shift
		USE="false"
		;;
            --resolve)
                RESOLVE_WORKSPACE=yes
                RESOLVE_FILESETS=yes
		shift
                ;;
            --resolve-workspace)
                shift
                ;;
            --resolve-filesets)
                RESOLVE_FILESETS=yes
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
	    local USE=$(jq -r '.auto_use_at_create // true' <<< "$_cfg")
            # Parse options first to get workspace and filesets
            parse_session_options "$@"
	    # The remaining args after options may contain an optional source session name
	    local src_session=""
	    if [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; then
		src_session="${REMAINING_ARGS[0]}"
	    fi

	    local workspace="__WORKSPACE_USED__"
	    local filesets_json="[]"
	    local src_ws
	    local src_fs

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
		else
		    # fallback if no metadata in source session
		    if [[ -n "$PARSED_WS" ]]; then
			workspace="$PARSED_WS"
		    fi
		    if [[ -n "$PARSED_FILESETS" ]]; then
			filesets_json="$PARSED_FILESETS"
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
		update_session "$name" "false" "$workspace" "$filesets_json"
		notice "Created session '$name' by copying from session '$src_session'"
	    else
		# Normal bootstrap new empty session
		mkdir -p "$path"
		update_session "$name" "true" "$workspace" "$filesets_json"
		notice "Created session '$name'"
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
	    if [[ "$USE" == "true" ]] ; then
		handle_x_use --no-use-notice session "$name"
	    fi
            ;;

        list|ls)
	    shift
	    ensure_session_exists "$(resolve_session_name)"
            handle_x_list session
            ;;

        use)
	    shift
            local name="$1"
            handle_x_use session "$name" # Handles optional name
            ;;

	unuse)
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
		echo "Session:   $name"
		if [[ -n "$ws" ]]; then
		    echo "Workspace: $ws"
		fi
		if [[ "$filesets_json" != "null" && "$filesets_json" != "[]" ]]; then
		    echo "Filesets:"
		    jq -r '.filesets[]' <<< "$session_json" | while IFS= read -r fs; do
			echo "  - $fs"
		    done
		fi
		echo -n "Files in "
		handle_session_command files "$name"
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
	    # Parse flags
	    local USE=$(jq -r '.auto_use_at_set // true' <<< "$_cfg")
	    parse_session_options "$@"
	    # Fallback to current if flags omitted
	    local ws="${PARSED_WS:-$current_ws}"
            if [[ -n "$ws" ]]; then
		validate_workspace_exists "$ws"
            fi
	    local filesets_json="${PARSED_FILESETS:-$current_fs}"

	    # Resolve markers if requested
            if [[ "$RESOLVE_WORKSPACE" == "yes" ]]; then
                # Resolve workspace marker __WORKSPACE_USED__
                if [[ "$ws" == "__WORKSPACE_USED__" ]]; then
                    ws="$(resolve_workspace_name)"
                fi
            fi

            if [[ "$RESOLVE_FILESETS" == "yes" ]]; then
                # Expand filesets markers (__WORKSPACE_FILESETS__, __SESSION_NAME__)
                local sess_name="$name"
                local ws_name="$ws"
                filesets_json=$(expand_filesets "$sess_name" "$ws_name" "$filesets_json")
            fi

	    # Ensure that any supplied session filesets exist in the workspace
	    local resworkspace="$(resolve_workspace_name "$ws")"
	    if [[ -n "$resworkspace" ]]; then
		ensure_filesets_exists \
		    "$name" \
		    "$ws" \
		    "$filesets_json"
	    fi
	    update_session "$name" "false" "$ws" "$filesets_json"
	    info "Updated session '$name' workspace='$ws' filesets=$filesets_json"
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
