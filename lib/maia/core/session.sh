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

  maia session <command> [args]
  maia session

Manage sessions, including creation, switching, and metadata.

COMMANDS

  create [options] <name> [<src>]
    Create a new session (empty history & outbox) or copy from an existing session.

  rename <old-name> <new-name>
    Rename a session and its session-associated fileset.

  list
    List all sessions (active one marked with *).

  set [options] [<name>]
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

  usage [--json] [today|last|<start> [<end>]]
    Show token usage for this session, today, the last API response, or a
    local-time range. With no range, show both session and today's totals.
    --json outputs machine-readable JSON.
    Accepted dates/times are:
      today or yesterday
      YYYY-MM-DD
      YYYY-MM-DDTHH:MM[:SS]
      YYYYMMDDTHHMMSS (the format stored in usage.json)
    A single date selects the whole day. A single timestamp selects from that
    time through now. With two values, the end is inclusive; date-only values
    include the whole day. 'last' returns the latest usage record and the
    configured max_input_tokens value.

  cancel
    Cancel the active AI operation in the current session.

  pause
    Pause the active AI operation at a safe loop boundary without killing tools.

  delete <name> [<name2> [...]]
    Delete a session (cannot delete active).

  exist [<name>]
    Returns 0 if the session exists
    Returns 1 if the session do not exist
    No output, to be used in scripts

OPTIONS

  --workspace <name>
    Set workspace <name>. See note below.

  --profile <name>
    Set profile <name>.

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

session_usage_command() {
    local json=false
    local -a range_args=()
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--json" ]]; then
            json=true
        else
            range_args+=("$arg")
        fi
    done

    local mode="summary"
    local start="" end="" label=""
    local today_key="$(date +%Y%m%d)"
    local today_label="$(date +%Y-%m-%d)"
    local max_input_tokens="$(get_setting max_input_tokens)"
    [[ "$max_input_tokens" =~ ^[0-9]+$ ]] || max_input_tokens=null

    case ${#range_args[@]} in
        0)
            ;;
        1)
            if [[ "${range_args[0]}" == "last" ]]; then
                mode="last"
            elif usage_is_date "${range_args[0]}"; then
                start="$(usage_normalize_time "${range_args[0]}" start)"
                end="$(usage_normalize_time "${range_args[0]}" end)"
                mode="range"
                case "${range_args[0]}" in
                    today) label="Usage today ($today_label)" ;;
                    yesterday)
                        local yesterday_label="$(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%d", localtime(time - 86400))')"
                        label="Usage yesterday ($yesterday_label)"
                        ;;
                    *) label="Usage on ${range_args[0]}" ;;
                esac
            else
                start="$(usage_normalize_time "${range_args[0]}" start)"
                end="$(date +%Y%m%dT%H%M%S)"
                [[ "$start" > "$end" ]] && die "Usage start time is in the future."
                mode="range"
                label="Usage from ${range_args[0]} through now"
            fi
            ;;
        2)
            start="$(usage_normalize_time "${range_args[0]}" start)"
            end="$(usage_normalize_time "${range_args[1]}" end)"
            [[ "$start" > "$end" ]] && die "Usage range start must not be after its end."
            mode="range"
            label="Usage from ${range_args[0]} through ${range_args[1]}"
            ;;
        *)
            die "Usage: maia session usage [--json] [today|last|<start> [<end>]]"
            ;;
    esac

    if [[ "$mode" == "last" && ${#range_args[@]} -ne 1 ]]; then
        die "The 'last' usage selector cannot be combined with a range."
    fi

    local usage_file="$(resolve_session_path)/usage.json"
    local output
    local -a jq_args=(--arg mode "$mode" --arg today "$today_key" --arg today_label "$today_label" --arg start "$start" --arg end "$end" --arg label "$label" --argjson json "$json" --argjson max_input_tokens "$max_input_tokens" -L "$MAIA_CORE_LIB_DIR" -f "$MAIA_CORE_LIB_DIR/usage-session.jq")
    if [[ "$json" == true ]]; then
        if [[ -f "$usage_file" ]]; then
            output="$(jq -c "${jq_args[@]}" "$usage_file")" || die "Unable to read usage data from '$usage_file'."
        else
            output="$(jq -c "${jq_args[@]}" <<< '[]')" || die "Unable to calculate session usage."
        fi
    else
        if [[ -f "$usage_file" ]]; then
            output="$(jq -r "${jq_args[@]}" "$usage_file")" || die "Unable to read usage data from '$usage_file'."
        else
            output="$(jq -r "${jq_args[@]}" <<< '[]')" || die "Unable to calculate session usage."
        fi
    fi

    printf '%s\n' "$output"
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

rename_session_fileset_value() {
    local value="$1"
    local old_name="$2"
    local new_name="$3"

    if [[ "$value" == "$old_name" ]]; then
        printf '%s' "$new_name"
        return
    fi

    # Session metadata normally stores filesets as a JSON array, but older
    # metadata may contain a single name or a whitespace/comma-separated list.
    if [[ "$value" == \[*\] ]] && jq -e . >/dev/null 2>&1 <<< "$value"; then
        jq -c --arg old "$old_name" --arg new "$new_name" '
            if type == "array" then
                map(if . == $old then $new else . end)
            elif type == "string" and . == $old then
                $new
            else
                .
            end
        ' <<< "$value"
        return
    fi

    local -a values=()
    local value_item
    read -ra values <<< "${value//,/ }"
    local result=""
    for value_item in "${values[@]}"; do
        [[ -n "$value_item" ]] || continue
        [[ "$value_item" == "$old_name" ]] && value_item="$new_name"
        result+="${result:+ }$value_item"
    done
    printf '%s' "$result"
}

rename_session_fileset_references() {
    local meta="$1"
    local old_name="$2"
    local new_name="$3"
    local field value updated

    for field in filesets extra_send_filesets; do
        value="$(myl_get "$meta" "$field" 2>/dev/null || true)"
        updated="$(rename_session_fileset_value "$value" "$old_name" "$new_name")"
        if [[ "$updated" != "$value" ]]; then
            myl_update "$meta" "$field" "$updated"
        fi
    done
}

# Return success only while the session lock owner is still active. Remove
# expired or orphaned lock files so the next request is not blocked by stale state.
session_lock_is_active() {
    local lockfile
    lockfile="$(session_lock_file)"
    [[ -r "$lockfile" ]] || return 1

    local lock_snapshot lpid="" lexpiry="" lstart="" now cstart="-1"
    lock_snapshot="$(cat "$lockfile" 2>/dev/null)" || return 1
    local -A lock_fields=()
    myl_load "$lockfile" lock_fields 2>/dev/null || true
    lpid="${lock_fields[lpid]:-}"
    lexpiry="${lock_fields[lexpiry]:-}"
    lstart="${lock_fields[lstart]:-}"

    local stale=false
    now="$(date +%s)"
    if [[ ! "$lpid" =~ ^[0-9]+$ || ! "$lexpiry" =~ ^[0-9]+$ ]]; then
        stale=true
    elif (( now >= lexpiry )); then
        stale=true
    elif [[ -e /proc/version ]]; then
        cstart="$(awk '{print $22}' "/proc/$lpid/stat" 2>/dev/null)"
        if [[ -z "$lstart" || -z "$cstart" || "$cstart" != "$lstart" ]]; then
            stale=true
        fi
    elif ! kill -0 "$lpid" 2>/dev/null; then
        stale=true
    fi

    if [[ "$stale" == true ]]; then
        # Re-read before unlinking so a replacement lock is not removed.
        if [[ "$(cat "$lockfile" 2>/dev/null)" == "$lock_snapshot" ]]; then
            release_lock "$lockfile"
        fi
        return 1
    fi
    return 0
}

# Atomically create a session marker containing its Unix expiry time.
# Print the expiry time so callers can tell a consumed marker from an expired one.
session_create_expiring_marker() {
    local marker_file="$1"
    local lifetime="${2:-30}"
    local now="$(date +%s)"
    local marker_expiry=$((now + lifetime))
    local marker_tmp="${marker_file}.${BASHPID:-$$}.$RANDOM.tmp"
    if ! printf '%s\n' "$marker_expiry" > "$marker_tmp" ||
        ! mv -f -- "$marker_tmp" "$marker_file"; then
        rm -f -- "$marker_tmp"
        notice "Unable to create the session marker."
        return 1
    fi
    printf '%s' "$marker_expiry"
}

session_pause_command() {
    local pause_file="$(resolve_session_path)/pause"

    if ! session_lock_is_active; then
        notice "No active AI operation to pause."
        return 1
    fi

    local pause_expiry
    if ! pause_expiry="$(session_create_expiring_marker "$pause_file" 30)"; then
        notice "Unable to create a pause marker."
        return 1
    fi

    # If the operation ended while the marker was being created, remove only
    # this pause marker so it cannot affect a later send.
    if ! session_lock_is_active; then
        expiring_marker_remove_if_matches "$pause_file" "$pause_expiry"
        notice "The active operation ended before the pause request was accepted."
        return 1
    fi

    notice "Pause requested; the active operation will stop at its next safe boundary."
}

session_cancel_command() {
    local lockfile="$(session_lock_file)"
    local cancel_file="$(resolve_session_path)/cancel"

    # Publish a pending cancellation before checking the lock. A send that is
    # already starting will either consume this marker after installing its
    # traps, or become visible through the session lock and be signalled below.
    local now cancel_expiry
    if ! cancel_expiry="$(session_create_expiring_marker "$cancel_file" 30)"; then
        die "Unable to create a pending cancellation marker."
    fi

    local deadline=$((SECONDS + 30))
    local lock_snapshot=""
    while (( SECONDS < deadline )); do
        now="$(date +%s)"
        if [[ ! -e "$cancel_file" ]]; then
            if (( now < cancel_expiry )); then
                notice "The pending send received the cancellation request."
                return
            fi
            warn "No active AI operation started before the cancellation request expired."
            return
        fi

        if session_lock_is_active; then
            lock_snapshot="$(cat "$lockfile" 2>/dev/null)" || lock_snapshot=""
            [[ -n "$lock_snapshot" ]] && break
        fi

        if expiring_marker_remove_if_expired "$cancel_file"; then
            warn "No active AI operation started before the cancellation request expired."
            return
        fi
        sleep 0.1
    done

    if [[ -z "$lock_snapshot" ]]; then
        expiring_marker_remove_if_expired "$cancel_file"
        notice "No active AI operation acquired the session lock within 30 seconds."
        return 1
    fi

    local lpid="" lstart=""
    local -A lock_fields=()
    myl_load "$lockfile" lock_fields 2>/dev/null || true
    lpid="${lock_fields[lpid]:-}"
    lstart="${lock_fields[lstart]:-}"
    [[ "$lpid" =~ ^[0-9]+$ ]] || {
        expiring_marker_remove_if_matches "$cancel_file" "$cancel_expiry"
        notice "No active AI operation to cancel."
        return 0
    }

    # Verify that the same lock and process still own this session before
    # signalling; the owner may have completed since the lock was observed.
    [[ "$(cat "$lockfile" 2>/dev/null)" == "$lock_snapshot" ]] || {
        expiring_marker_remove_if_matches "$cancel_file" "$cancel_expiry"
        notice "The active operation changed before cancellation could be sent."
        return 1
    }
    if [[ -e /proc/version ]]; then
        local current_start="$(pid_starttime "$lpid" 2>/dev/null)"
        if [[ -z "$lstart" || -z "$current_start" || "$current_start" != "$lstart" ]]; then
            expiring_marker_remove_if_matches "$cancel_file" "$cancel_expiry"
            notice "No active AI operation to cancel."
            return 0
        fi
    elif ! kill -0 "$lpid" 2>/dev/null; then
        expiring_marker_remove_if_matches "$cancel_file" "$cancel_expiry"
        notice "No active AI operation to cancel."
        return 0
    fi

    if ! kill -INT "$lpid" 2>/dev/null; then
        expiring_marker_remove_if_matches "$cancel_file" "$cancel_expiry"
        notice "The active operation ended before cancellation could be sent."
        return 0
    fi
    # Once this operation was known to hold the session lock, the signal is
    # the cancellation mechanism; discard the startup marker so it cannot
    # affect a later send. Preserve a concurrent cancellation with a newer
    # expiry if one was published in the meantime.
    expiring_marker_remove_if_matches "$cancel_file" "$cancel_expiry"
    notice "Cancellation signal sent to the active AI operation; waiting for it to stop."

    # A successful kill only confirms that the signal was delivered. Wait for
    # the operation we signalled to release its lock before reporting success.
    local stop_deadline=$((SECONDS + 30))
    while (( SECONDS < stop_deadline )); do
        local current_lock
        current_lock="$(cat "$lockfile" 2>/dev/null)" || current_lock=""
        if [[ "$current_lock" != "$lock_snapshot" ]]; then
            notice "Cancellation confirmed; the active operation released its session lock."
            return 0
        fi
        if ! session_lock_is_active; then
            notice "Cancellation confirmed; the active operation released its session lock."
            return 0
        fi
        sleep 0.1
    done

    notice "Cancellation was requested, but the active operation did not release its session lock within 30 seconds."
    return 1
}

handle_session_command() {
    [[ "$1" =~ ^-h|--help$ ]] && session_usage

    local scope="session"
    load_settings "$scope"

    local cmd="$1"
	case "$cmd" in
	usage)
	    shift
	    . "$MAIA_CORE_LIB_DIR/usage-common.sh"
	    session_usage_command "$@"
	    ;;
	cancel)
	    shift
	    [[ $# -eq 0 ]] || die "Usage: maia session cancel"
	    session_cancel_command
	    ;;
	pause)
	    shift
	    [[ $# -eq 0 ]] || die "Usage: maia session pause"
	    session_pause_command
	    ;;
	lock-status)
	    # Lightweight read-only status used by the web client after a stream
	    # disconnects; unlike history/show, this does not load conversation data.
            if session_lock_is_active; then
		printf '{"locked":true}\n'
            else
		printf '{"locked":false}\n'
            fi
            return 0
	    ;;
	create)
	    shift
            RESOLVE_FILESETS=false
            parse_session_options "$@"
            if [[ ${#REMAINING_ARGS[@]} -eq 0 ]]; then
                die "Session name is required."
            fi
            local name="${REMAINING_ARGS[0]}"
	    if [[ "$name" == "_EMPTY_" ]] ; then
		die "Session name _EMPTY_ is not allowed."
	    fi
            local path="$(resolve_session_path "$name")"
	    if [[ -d "$path" ]] ; then
		die "Session '$name' already exists."
	    fi
	    trigger_event "pre-session-create $name"
            # The remaining args after options contain the session name and
            # may contain an optional source session name.
            local src_session=""
            if [[ ${#REMAINING_ARGS[@]} -gt 1 ]]; then
                src_session="${REMAINING_ARGS[1]}"
            fi

	    local ws_source=" (from default_workspace configuration)"
	    local workspace=$(get_setting default_workspace)
	    local profile_source=" (from default_profile configuration)"
	    local profile=$(get_setting default_profile)
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
		    filesets="$(get_setting default_session_filesets)"
		fi
		if [[ -v PARSED_EXTRA_SEND_FILESETS ]]; then
                    extra_send_filesets="$PARSED_EXTRA_SEND_FILESETS"
		else
		    extra_send_filesets="$(get_setting default_session_extra_send_filesets)"
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
		    if [[ "$base_item" != "logs" && "$base_item" != "jobs" && "$base_item" != "usage.json" ]]; then
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
		read_file "$meta"
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
	    session_content_extract "$name" | jq -r -f "$MAIA_CORE_LIB_DIR/files-json-to-markdown-all.jq"
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

        rename)
            shift
            [[ $# -eq 2 ]] || die "Usage: maia session rename <new-name> <old-name>"
            local old_name="$1"
            local new_name="$2"
            [[ "$new_name" =~ ^[A-Za-z0-9_.%+-]+$ ]] || die "Invalid new session name '$new_name'."
            [[ "$old_name" =~ ^[A-Za-z0-9_.%+-]+$ ]] || die "Invalid old session name '$old_name'."
            [[ "$new_name" != "_EMPTY_" && "$old_name" != "_EMPTY_" ]] || die "Session name _EMPTY_ is not allowed."
            [[ "$new_name" != "$old_name" ]] || die "The new and old session names must differ."

            local old_path="$(resolve_session_path "$old_name")"
            local new_path="$(resolve_session_path "$new_name")"
            [[ -d "$old_path" ]] || die "Session '$old_name' does not exist."
            [[ ! -e "$new_path" ]] || die "Session '$new_name' already exists."
            [[ ! -e "$old_path/lock" ]] || die "Session '$old_name' is currently locked."

            local old_meta="$(resolve_session_meta "$old_name")"
            [[ -f "$old_meta" ]] || die "Session '$old_name' does not have metadata."
            local workspace="$(read_session_workspace_raw "$old_name")"
            local workspace_dir=""
            local old_fileset=""
            local new_fileset=""
            local fileset_moved=false
            if [[ -n "$workspace" ]]; then
                workspace_dir="$(resolve_workspace_path "$workspace")"
                if [[ -d "$workspace_dir" ]]; then
                    old_fileset="$workspace_dir/${old_name}.fileset"
                    new_fileset="$workspace_dir/${new_name}.fileset"
                    [[ ! -e "$old_fileset" || ! -e "$new_fileset" ]] || \
                        die "Cannot rename fileset: '$new_name.fileset' already exists."
                fi
            fi

            trigger_event "pre-session-rename $old_name $new_name"
            local metadata_backup="${old_meta}.rename-backup.$$"
            cp -p -- "$old_meta" "$metadata_backup" || die "Unable to prepare session metadata for rename."

            if [[ -n "$old_fileset" && -e "$old_fileset" ]]; then
                mv -- "$old_fileset" "$new_fileset" || {
                    rm -f -- "$metadata_backup"
                    die "Unable to rename fileset '$old_name' to '$new_name'."
                }
                fileset_moved=true
            fi

            if ! rename_session_fileset_references "$old_meta" "$old_name" "$new_name"; then
                cp -p -- "$metadata_backup" "$old_meta"
                if [[ "$fileset_moved" == true ]]; then
                    mv -- "$new_fileset" "$old_fileset" || true
                fi
                rm -f -- "$metadata_backup"
                die "Unable to update fileset references in session metadata."
            fi

            if ! mv -- "$old_path" "$new_path"; then
                cp -p -- "$metadata_backup" "$old_meta"
                if [[ "$fileset_moved" == true ]]; then
                    mv -- "$new_fileset" "$old_fileset" || true
                fi
                rm -f -- "$metadata_backup"
                die "Unable to rename session '$old_name' to '$new_name'."
            fi
            rm -f -- "$new_path/$(basename "$metadata_backup")"
            if ! rename_session_in_groups "$old_name" "$new_name"; then
                trigger_event "post-session-rename $old_name $new_name"
                die "Session '$old_name' was renamed to '$new_name', but one or more session groups could not be updated. Please inspect the group files."
            fi
            notice "Renamed session '$old_name' to '$new_name'."
            trigger_event "post-session-rename $old_name $new_name"
            ;;

	set)
	    shift
            RESOLVE_FILESETS=false
            parse_session_options "$@"
            local name="${REMAINING_ARGS[0]:-$(resolve_session_name)}"
	    trigger_event "pre-session-update $name"
	    # Load current values
	    local meta="$(resolve_session_meta "$name")"
            [[ -f "$meta" ]] || die "Session '${name:-$(resolve_session_name)}' does not exist"
            local current_ws="$(myl_get "$meta" 'workspace')"
	    local current_profile="$(myl_get "$meta" 'profile')"
	    local current_fs="$(myl_get "$meta" 'filesets')"
	    local current_extra_fs="$(myl_get "$meta" 'extra_send_filesets')"
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
		local workspace=""
		if [[ "$session" != "default" && -d "$(resolve_session_path "$session")" ]]; then
		    workspace="$(read_session_workspace_raw "$session")"
		fi
		handle_x_delete session "$session" # Handles empty name
		if [[ -n "$workspace" ]]; then
		    local workspace_dir="$(resolve_workspace_path "$workspace")"
		    if [[ -n "$workspace_dir" ]]; then
			rm -f -- "$workspace_dir/${session}.fileset"
		    fi
		fi
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
