#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

session_usage() {
    cat <<'EOF'
USAGE

  maia session <command> [options]
  maia session

Manage sessions, including creation, switching, and metadata.

COMMANDS

  create <name> [--workspace <ws>] [resolve-options] [--filesets <fs>[,fs2...]] [<src>]
    Create a new session (empty history & outbox) or copy from an existing session.

  list
    List all sessions (active one marked with *).

  set [<name>] [--workspace <ws>] [resolve-options] [--filesets <fs>[,fs2...]]
    Set properties for a session.

  edit [<name>]
    Edit the session in an editor.

  show [options] [<name>]
    Show session metadata.
    Options are:
      --raw|--json  Output in json format

  content [<name>]
    Show the file content in this session.

  files [<name>]
    Show a list of files in this session.

  instructions
    Show the instruction content in this session.

  tasks
    Show the task content in this session.

  delete <name> [<name2> [...]]
    Delete a session (cannot delete active).

  exist [<name>]
    Returns 0 if the session exists
    Returns 1 if the session do not exist
    No output, to be used in scripts

OPTIONS

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
     Same as --resolve-filesets

  --resolve-filesets
     Resolve __WORKSPACE_FILESETS__ to the filesets of the workspace in use.

  --noresolve
     Same as --noresolve-filesets

  --noresolve-filesets
     Do not resolve __WORKSPACE_FILESETS__ to the filesets of the workspace in use.

NOTES

  When <name> is optional it defaults to the active session.

  When no command is given it defaults to maia session use.

  A session is described as defunct if the directory exist, but the session metadata do not.
  Such sessions may contain history data and an outbox. Such sessions can be deleted only.

  --filesets supports the special marker "__WORKSPACE_FILESETS__" to
    represent all workspace filesets and "__SESSION_NAME__" to represent the name of the
    current session.

EOF
    exit 0
}

parse_session_options() {
    REMAINING_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)
                shift
                (( $# >= 1 )) || { error "The option --workspace requires an argument."; session_usage; }
                PARSED_WS="$1"; shift
                ;;
	    --profile)
                shift
                (( $# >= 1 )) || { error "The option --profile requires an argument."; session_usage; }
                PARSED_PROFILE="$1"; shift
		;;
            --filesets|--fileset)
                shift
		[[ $# -ge 1 ]] || { die "The option --filesets requires a comma-separated list."; }
                IFS=',' read -r -a _arr <<< "$1"
		PARSED_FILESETS="${_arr[@]}"
                shift
                ;;
	    --extra-send-filesets|--extra)
		local OPT="$1"
		shift
                [[ $# -ge 1 ]] || { die "The option $OPT requires a comma-separated list."; }
                IFS=',' read -r -a _arr <<< "$1"
                PARSED_EXTRA_SEND_FILESETS="${_arr[@]}"
                shift
		;;
            --resolve)
                RESOLVE_FILESETS=true
		shift
                ;;
            --resolve-filesets)
                RESOLVE_FILESETS=true
                shift
                ;;
            --noresolve)
                RESOLVE_FILESETS=false
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
	    trigger_event "pre-session-create $name"
            # Parse options first to get workspace, filesets and extra_send_filesets
	    RESOLVE_FILESETS=false
            parse_session_options "$@"
	    # The remaining args after options may contain an optional source session name
	    local src_session=""
	    if [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; then
		src_session="${REMAINING_ARGS[0]}"
	    fi

	    local ws_source=" (from default_workspace configuration)"
	    local workspace=$(get_config default_workspace)
	    local profile_source=" (from default_profile configuration)"
	    local profile=$(get_config default_profile)
	    if [[ "$workspace" == "__SESSION_WORKSPACE__" ]] ; then
		ws_source=" (resolved from current session)"
		workspace="$(resolve_workspace_name)"
	    fi
	    local filesets=""
	    local extra_send_filesets=""
	    local src_ws
	    local src_fs
	    local src_extra_fs

	    local extracopyinfo=""
	    # If copying from a source session, read its metadata first to get defaults
	    if [[ -n "$src_session" ]]; then
		local src_path="$(resolve_session_path "$src_session")"
		if [[ ! -d "$src_path" ]]; then
		    die "Source session '$src_session' does not exist."
		fi
		local src_meta="$(resolve_session_meta "$src_session")"
		if [[ -f "$src_meta" ]]; then
		    # Read workspace, profile and filesets from source session
		    src_ws="$(myl_get "$src_meta" 'workspace')"
		    src_profile="$(myl_get "$src_meta" 'profile')"
		    src_fs="$(myl_get "$src_meta" 'filesets')"
		    src_extra_fs="$(myl_get "$src_meta" 'extra_send_filesets')"

		    # Use source session workspace/filesets as defaults if not overridden by options
		    if [[ ! -v PARSED_WS && -n "$src_ws" ]]; then
			ws_source=" (from source session)"
			workspace="$src_ws"
		    elif [[ -v PARSED_WS ]]; then
			ws_source=" (from --workspace)"
			workspace="$PARSED_WS"
		    fi

		    if [[ ! -v PARSED_PROFILE && -n "$src_profile" ]]; then
			profile_source=" (from source session)"
			profile="$src_profile"
		    elif [[ -v PARSED_PROFILE ]]; then
			profile_source=" (from --profile)"
			profile="$PARSED_PROFILE"
		    fi

		    if [[ ! -v PARSED_FILESETS && -n "$src_fs" ]]; then
			filesets="$src_fs"
		    elif [[ -v PARSED_FILESETS ]]; then
			filesets="$PARSED_FILESETS"
		    fi

		    if [[ ! -v PARSED_EXTRA_SEND_FILESETS && -n "$src_extra_fs" ]]; then
			extra_send_filesets="$src_extra_fs"
                    elif [[ -v PARSED_EXTRA_SEND_FILESETS ]]; then
			extra_send_filesets="$PARSED_EXTRA_SEND_FILESETS"
                    fi
		else
		    # fallback if no metadata in source session
		    if [[ -v PARSED_WS ]]; then
			ws_source=" (from --workspace)"
			workspace="$PARSED_WS"
		    fi
		    if [[ -v PARSED_PROFILE ]]; then
			profile_source=" (from --profile)"
			profile="$PARSED_PROFILE"
		    fi
		    if [[ -v PARSED_FILESETS ]]; then
			filesets="$PARSED_FILESETS"
		    fi
		    if [[ -v PARSED_EXTRA_SEND_FILESETS ]]; then
			extra_send_filesets="$PARSED_EXTRA_SEND_FILESETS"
                    fi
		fi
	    else
		# No source session, use options or defaults
		if [[ -v PARSED_WS ]] ; then
		    ws_source=" (from --workspace)"
		    workspace="$PARSED_WS"
		fi
		if [[ -v PARSED_PROFILE ]] ; then
		    profile_source=" (from --profile)"
		    profile="$PARSED_PROFILE"
		fi
		if [[ -v PARSED_FILESETS ]]; then
		    filesets="$PARSED_FILESETS"
		else
		    filesets="$(get_config default_session_filesets)"
		fi
		if [[ -v PARSED_EXTRA_SEND_FILESETS ]]; then
                    extra_send_filesets="$PARSED_EXTRA_SEND_FILESETS"
		else
		    extra_send_filesets="$(get_config default_session_extra_send_filesets)"
		fi
	    fi

	    # Validate workspace exists
	    if [[ -n "$workspace" ]]; then
		validate_workspace_exists "$workspace"
	    fi
	    if [[ -n "$profile" ]]; then
		validate_profile_exists "$profile"
		if ! profile_allowed "$profile" ; then
		    die "Profile '$profile' is not allowed."
		fi
	    fi

	    if [[ -n "$src_session" ]]; then
		# Copy session directory from src_session to new session directory, excluding logs and jobs
		mkdir -p "$path"
		# Copy all except logs directory
		shopt -s dotglob nullglob
		for item in "$src_path"/*; do
		    base_item="$(basename "$item")"
		    if [[ "$base_item" != "logs" && $base_item != "jobs" ]]; then
			if [[ -d "$item" ]]; then
			    cp -a "$item" "$path/"
			else
			    cp "$item" "$path/"
			fi
		    fi
		done
		shopt -u dotglob nullglob

		if [[ -n "$src_ws" ]] ; then
		    # Update session metadata file with new workspace and filesets
		    # If src_fs is exactly ["src_session"], then
		    if [[ "$src_fs" == "$src_session" ]]; then
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
			filesets="$name"
		    fi
		fi
		#
		update_session "$name" "false" "$workspace" "$profile" "$filesets" "$extra_send_filesets"
		extracopyinfo=" by copying from session '$src_session'"
	    else
		# Normal bootstrap new empty session
		mkdir -p "$path"
		update_session "$name" "true" "$workspace" "$profile" "$filesets" "$extra_send_filesets"
		local extra=""
		if [[ -n "$workspace" ]] ; then
		    extra+=" with workspace '$workspace'$ws_source"
		else
		    extra+=" with no workspace$ws_source"
		fi
		if [[ -n "$profile" ]] ; then
		    extra+=" and with profile '$profile'$profile_source"
		else
		    extra+=" and with no profile$profile_source"
		fi
	    fi
	    notice "Created session '$name'$extracopyinfo$extra."

            if [[ "$RESOLVE_FILESETS" == "true" ]]; then
                # Expand filesets markers (__WORKSPACE_FILESETS__, __SESSION_NAME__)
                local sess_name="$name"
                local ws_name="$ws"
                filesets=$(expand_filesets "$sess_name" "$ws_name" "$filesets")
		extra_send_filesets=$(expand_filesets "$sess_name" "$ws_name" "$extra_send_filesets")
            fi
	    # If filesets include __SESSION_NAME__, copy the old session fileset file to the new session fileset file
	    if [[ -n "$src_ws" && -n "$src_fs" && \
		      "$src_fs" == *"__SESSION_NAME__"* && \
		      "$filesets" == *"__SESSION_NAME__"* ]]; then
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
		    "$filesets"
		# Also ensure extra_send_filesets exist
		ensure_filesets_exists \
                    "$name" \
                    "$workspace" \
                    "$extra_send_filesets"
	    fi
	    trigger_event "post-session-create"
	    ;;

	edit)
	    shift
            local name="${1:-$(resolve_session_name)}"
	    trigger_event "pre-session-update $name"
	    ensure_session_exists "$name"
            handle_x_edit "session" "session" "$name" # Handles optional name, but we resolve it
	    trigger_event "post-session-update" "$name"
            ;;

	exist)
	    shift
            local name="${1:-$(resolve_session_name)}"
            local meta="$(resolve_session_meta "$name")"
            [[ -f "$meta" ]] || exit 1
	    exit 0
	    ;;

        list|ls)
	    shift
	    ensure_session_exists "$(resolve_session_name)"
            handle_x_list session
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
            # Show session.myl
            local name="${1:-$(resolve_session_name)}"
	    ensure_session_exists "$name"
            local meta="$(resolve_session_meta "$name")"
            [[ -f "$meta" ]] || die "Session '${name:-$(resolve_session_name)}' does not exist"
	    if (( raw_output )); then
		read_file "$meta" cr
	    else
		local ws="$(myl_get "$meta" 'workspace')"
		local profile="$(myl_get "$meta" 'profile')"
		local filesets="$(myl_get "$meta" 'filesets')"
		local extra_send_filesets="$(myl_get "$meta" 'extra_send_filesets')"
		echo "Session:   $name"
		if [[ -n "$profile" ]] ; then
		    echo "Profile:   $profile"
		fi
		if [[ -n "$ws" ]]; then
		    local note=""
		    local ws_name="$ws"
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
		    if [[ -n "$filesets" ]]; then
			echo "Filesets:"
			local fs
			for fs in $filesets ; do
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
		    if [[ -n "$extra_send_filesets" ]] ; then
			echo "Extra send filesets:"
			local fs
			for fs in $extra_send_filesets ; do
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
            local name="${1:-$(resolve_session_name)}"
	    session_content_extract --list "$name"
	    ;;

        contents|content)
	    shift
            local name="${1:-$(resolve_session_name)}"
	    session_content_extract "$name" | jq -r -f "$MAIA_CORE_LIB_DIR/files-json-to-markdown.jq"
            ;;

        instructions|instruction)
	    shift
	    init_instruction_search_dirs
	    session_instruction_extract
            ;;

        tasks|task)
	    shift
	    init_task_search_dirs
	    session_task_extract
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
	    trigger_event "pre-session-update $name"
	    # Load current values
	    local meta="$(resolve_session_meta "$name")"
            [[ -f "$meta" ]] || die "Session '${name:-$(resolve_session_name)}' does not exist"
            local current_ws="$(myl_get "$meta" 'workspace')"
	    local current_profile="$(myl_get "$meta" 'profile')"
	    local current_fs="$(myl_get "$meta" 'filesets')"
	    local current_extra_fs="$(myl_get "$meta" 'extra_send_filesets')"
	    # Parse flags
	    RESOLVE_FILESETS=false
	    parse_session_options "$@"
	    # Fallback to current if flags omitted
	    local ws="${PARSED_WS-$current_ws}"
            if [[ -n "$ws" ]]; then
		validate_workspace_exists "$ws"
            fi
	    local profile="${PARSED_PROFILE-$current_profile}"
            if [[ -n "$profile" ]]; then
		validate_profile_exists "$profile"
            fi
	    local filesets="${PARSED_FILESETS-$current_fs}"
	    local extra_send_filesets="${PARSED_EXTRA_SEND_FILESETS-$current_extra_fs}"

            if [[ "$RESOLVE_FILESETS" == "true" ]]; then
                # Expand filesets markers (__WORKSPACE_FILESETS__, __SESSION_NAME__)
                local sess_name="$name"
                local ws_name="$ws"
                filesets=$(expand_filesets "$sess_name" "$ws_name" "$filesets")
		extra_send_filesets=$(expand_filesets "$sess_name" "$ws_name" "$extra_send_filesets")
            fi

	    # Ensure that any supplied session filesets exist in the workspace
	    local resworkspace="$(resolve_workspace_name "$ws")"
	    if [[ -n "$resworkspace" ]]; then
		ensure_filesets_exists \
		    "$name" \
		    "$ws" \
		    "$filesets"
		ensure_filesets_exists \
                    "$name" \
		    "$ws" \
                    "$extra_send_filesets"
	    fi
	    update_session "$name" "false" "$ws" "$profile" "$filesets" "$extra_send_filesets"
	    info "Updated session '$name' workspace='$ws' profile='$profile' filesets=$filesets extra_send_filesets=$extra_send_filesets"
	    trigger_event "post-session-update $name"
	    ;;
	
	delete)
	    shift
	    local session
	    for session in "$@" ; do
		trigger_event "pre-session-delete $session"
	    done
	    for session in "$@" ; do
		handle_x_delete session "$session" # Handles empty name
	    done
	    for session in "$@" ; do
		trigger_event "post-session-delete $session"
	    done
            ;;

	"")
	    local session="$(resolve_session_name)"
	    local meta="$(resolve_session_meta)"
	    if [[ ! -e "$meta" ]] ; then
		session+="!"
	    fi
	    echo "$session"
	    ;;
        *)
            session_usage
            ;;
    esac
}
