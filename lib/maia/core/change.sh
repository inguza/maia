#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
change_usage() {
    cat <<'EOF'
USAGE

  maia change <command> [options] [ID…]

Manage change suggestions and their application.

COMMANDS

  list|ls [list options ...]
    List change suggestions, grouped by base ID.

    List options are:
     --pending
     --applied
     --skipped
     --finished
     --failed
     --running
     --all
     --all-sessions
     --all-states

  show [--raw] [<ID>]
    Display metadata and change suggestions.

  edit [--assign-path <path>] [<ID> [<ID>...]]
    Edit change metadata, optionally reassign path.

  apply [--dry-run] [--keep-history] [--update-history] [<ID> [<ID>...]]
    Apply changes (patch files) for a change set.

  run [<ID> [<ID>...]]
    Apply cahges by running the shell commands.

  do [<ID> [<ID>...]]
    Do the proposed actions.

  save <filename> <ID>

  applied [--update-history] [<ID> [<ID>...]]
    Mark a change status as applied.

  pending [--update-history] [<ID> [<ID>...]]
    Mark a change status as pending.

  skipped [--update-history] [<ID> [<ID>...]]
    Mark a change status as skipped.

  running [--update-history] [<ID> [<ID>...]]
    Mark a change status as running.

  finished [--update-history] [<ID> [<ID>...]]
    Mark a change status as finished.

  failed [--update-history] [<ID> [<ID>...]]
    Mark a change status as failed.

  delete [<ID> [<ID>...]]
    Delete change artifacts.

OPTIONS COMMON TO APPLY/APPLIED/SKIP:

  --update-history
    Rewrite history when fully applied/skipped.

  --keep-history
    Retain history when fully applied/skipped.

  --dry-run
    (apply) Do not write changes.

  --session <NAME>
    Work on session NAME

OPTIONS

  -h, --help
    Show this message.

EXAMPLES

    maia change list --pending
      List all pending changes.

    maia change apply 20250513T142512Z-abcd1234
      Apply specified change set.

    maia change edit --assign-path src/ 20250513T142512Z-abcd1234
      Edit change metadata and reassign path.

NOTES

  Changes represent suggestions for patching files and can be applied or skipped.

  When the ID argument is omitted for these commands, the last 'set' change ID is used by default.
EOF
    exit 0
}

prune_history() {
    local idbase=$1      # e.g. 20250513T142512Z-abcd1234
    local action=$2      # "applied" or "skipped"

    info "Pruning history for $idbase (applied)"

    # Map action to state suffix used in filenames
    local state_suffix
    case "$action" in
        apply)   state_suffix="applied" ;;
        applied) state_suffix="applied" ;;
        skip)    state_suffix="skipped" ;;
        skipped) state_suffix="skipped" ;;
        pending) state_suffix="pending" ;;
        *)       state_suffix="$action" ;;  # fallback
    esac

    # Locate root metadata file
    local root_meta="$changes_dir/$session/${idbase}-+-${state_suffix}.myl"
    if [[ ! -f "$root_meta" ]]; then
        notice "Root metadata file $root_meta not found; skipping history pruning for change $idbase"
        return
    fi

    # Resolve history file for that session
    local hist_file="$(resolve_history_meta "$session")"
    if [[ ! -f "$hist_file" ]]; then
        notice "History file for session '$session' does not exist; skipping pruning"
        return
    fi

    # split idbase into timestamp and sha
    local ts="${idbase%%-*}"    # “2025-05-14T09:02:56”
    local id="${idbase#*-}"    # “1ed80fc4”

    # 1) Load the original <idbase>.txt
    local instructions_file="$changes_dir/$session/${idbase}.txt"
    if [[ ! -f "$instructions_file" ]]; then
	# We do not log since this is the normal case for file-* tools
	return
    fi
    local instructions=$(read_file "$instructions_file")

    # 2) Append the status line
    if [[ "$action" == "applied" ]]; then
        instructions+="

The above has been considered and the history is pruned."
    else
        instructions+="

The above has been skipped and the history is pruned."
    fi

    # 3) Rewrite the history entry's content
    #    We match by timestamp+shaid prefix == idbase
    exclusive_json_modify \
	"$hist_file" \
	--arg ts "$ts" \
	--arg id "$id" \
	--arg newContent "$instructions" \
	'map(
          if (.timestamp == $ts and .id == $id)
          then .content = $newContent
          else .
          end
        )'
}

# get_last_set_change_id
# Scans the changes directory and returns the last change ID of type 'set'
# (determined by presence of '+' in the filename) sorted lexically.
# Returns empty string if none found.
find_last_set_change_id() {
    local session="$1"
    shopt -s nullglob
    local last_id=""
    local files=( "$changes_dir"/$session/*-+-*.myl )
    if (( ${#files[@]} == 0 )); then
        echo ""
        return
    fi
    # Extract IDs by stripping directory and trailing '-+.myl'
    local ids=()
    for f in "${files[@]}"; do
        local fname=$(basename -- "$f")
        local id="${fname%-+-*.myl}"
        ids+=( "$id" )
    done
    # Sort lexically and pick last
    IFS=$'\n' sorted=($(sort <<<"${ids[*]}"))
    unset IFS
    last_id="${sorted[-1]}"
    echo "$last_id"
}

# Pre-check: record if any sub-entry was previously pending
pre_check() {
    local session="$1"
    local base="$2"
    local pending=false

    # Make sure unmatched globs vanish
    shopt -s nullglob

    # Look at every sub-entry JSON (index "+" or digits)
    for f in "$changes_dir/$session/${base}-"*".myl"; do
	[[ -f "$f" ]] || continue
	if [[ "$(get_status "$f")" == "pending" ]]; then
	    pending=true
	    break
	fi
    done

    PREVIOUSLY_PENDING=$pending
}

# Post-check: if any were pending, and now all match $2, update base and prune
post_check() {
    local session="$1"
    local base="$2"
    local status="$3"
    local all_match=true
    shopt -s nullglob
    # Verify every sub-entry JSON now has .status != pending
    for f in "$changes_dir/$session/${base}-"*".myl"; do
	if [[ "$(get_status "$f")" == "pending" ]]; then
	    all_match=false
	    break
	fi
    done

    # If we transitioned from some pending to all-matching, bump the base
    if [[ "$PREVIOUSLY_PENDING" == true && "$all_match" == true ]]; then
	# Prune history if configured
	[[ "$UPDATE_HISTORY" == true ]] && prune_history "$base" "$status"
    fi
}

change_list() {
    local session="$1"
    shift
    # 1) parse status flags
    local status_filter=""
    local session_filter="$session"
    local print_sessname=0
    while [[ "$1" =~ ^-- ]]; do
	case "$1" in
	    --pending)
		status_filter="pending"
		shift
		;;
	    --applied)
		status_filter="applied"
		shift ;;
	    --skipped)
		status_filter="skipped"
		shift
		;;
	    --finished)
		status_filter="finished"
		shift
		;;
	    --failed)
		status_filter="failed"
		shift
		;;
	    --running)
		status_filter="running"
		shift
		;;
	    --all)
		status_filter="*"
		session_filter="*"
		print_sessname=1
		shift
		;;
	    --all-sessions)
		session_filter="*"
		print_sessname=1
		shift
		;;
	    --all-states)
		status_filter="*"
		shift
		;;
	    *)
		die "Unknown option: $1"
		;;
	esac
    done

    # Default to showing only pending if no filter specified
    if [[ -z "$status_filter" ]]; then
        status_filter="@(pending|running|failed)"
    fi

    # 2) bail if no directory
    if [[ ! -d "$changes_dir" ]]; then
	notice "No changes found"
	return
    fi

    # 3) collect only the top-level change IDs (no "-n" suffix)
    shopt -s nullglob
    # 4) print a single header
    printf "  %-30s %-10s %-10s %s
" "ID" "TYPE" "STATUS" "FILENAME"
    # 5) for each base, print its status and then its sub-entries
    LC_COLLATE=C
    local scdir
    for scdir in "$changes_dir"/${session_filter}; do
	local scname=$(basename $scdir)
	local scprinted=0
	# We do not need to check that $scdir is a directory, because this
	# for look will do that anyway
	shopt -s extglob
	for file in "$scdir"/*-${status_filter}.myl; do
	    local fname base status index id type filename
	    if [[ $scprinted -eq 0 ]] ; then
		if [[ $print_sessname -eq 1 ]] ; then
		    printf "%s:
" \
		    $scname
		    scprinted=1
		fi
	    fi
	    fname=$(basename $file)
	    base="${fname%.myl}"                # => "...-+-pending" or "...-0-pending"
	    status=$(get_status "$file")
	    # 3) Extract the “index” field (either "+" or a digit)
	    tmp="${base%-*}"                     # => "...-+-" or "...-0"
	    index="${tmp##*-}"                   # => "+" or "0"
	    # 4) Compute filebase = everything up to (and including) the index
	    filebase="$tmp"                      # => "2025-05-17T19:10:54-81610843-+"
            #    or "…-81610843-0"
	    type=$(myl_get "$file" 'type')
	    filename=$(myl_get "$file" 'filename')
	    # 5) Compute id: drop the “-+” for a set file, keep “-0” for numbered
	    if [[ "$index" == "+" ]]; then
		# remove the trailing “-+”
		id="${filebase%-+}"                # => "2025-05-17T19:10:54-81610843"
		printf "  %-30s %-10s %-10s %s
" \
		"$id" "set" "$status" ""
	    else
		# keep the trailing “-0” (or any digit)
		id="$filebase"                     # => "…-81610843-0"
		printf "   %-29s %-10s %-10s %s
" \
		" $id" "$type" "$status" "$filename"
	    fi
	done
    done
}

get_status() {
    local file="$1" fname base status
    fname="$(basename -- "$file")"      # strip directory
    base="${fname%.*}"                  # remove extension
    status="${base##*-}"                # take text after last “-”
    echo "$status"
}

add_file_to_session_filesets() {
    local file="$1"
    local session="$2"
    local ws_name=$(resolve_session_workspace "$session")
    local expanded_filesets_json=$(get_session_expanded_filesets "$session")
    local sess_fs
    mapfile_from_json sess_fs "$expanded_filesets_json"
    local workspace_root="$(resolve_workspace_root "$ws_name")"
    local ws_root=$(resolve_workspace_path "$ws_name")
    if [[ ! -e "$workspace_root/$file" ]] ; then
	warn "File $file does not exist in workspace $ws_name."
	return
    fi
    local fsname
    for fsname in "${sess_fs[@]}"; do
	local fs="$ws_root/${fsname}.fileset"
	if [[ ! -e "$fs" ]] ; then
	    warn "Fileset '$fs' does not exist in worspace '$ws_name'."
	    continue
	fi
	if [[ ! -w "$fs" ]] ; then
	    warn "Fileset '$fs' read-only, skipping."
	    continue
	fi
	add_file_to_fileset_file "$file" "$fs"
    done
}

apply_patch() {
    local revert=false
    if [[ "$1" == "-R" ]] ; then
	revert=true
	shift
    fi
    local workspace_root="$1"; shift
    pushd "$workspace_root" >/dev/null  || die "Cannot cd to workspace root"
    for pf in "$@"; do
	if [[ "$revert" == false ]] ; then
	    pid=$(basename -- "$pf" -pending.patch)
	    patch --dry-run -p1 < "$pf" || die "Dry-run failed on $pid"
	else
	    pid=$(basename -- "$pf" -applied.patch)
	    patch -R --dry-run -p1 < "$pf" || die "Dry-run failed on $pid"
	fi
    done
    [[ "$DRY_RUN" == true ]] && {
	popd >/dev/null
	return
    }
    for pf in "$@"; do
	if [[ "$revert" == false ]] ; then
	    pid=$(basename -- "$pf" -pending.patch)
	    local metaf="$changes_dir/$session/${pid}-pending.myl"
	    patch -p1 < "$pf" || die "Apply failed on $pid"
	    notice "Applied change '$pid'"
	else
	    pid=$(basename -- "$pf" -applied.patch)
	    local metaf="$changes_dir/$session/${pid}-applied.myl"
	    patch -R -p1 < "$pf" || die "Revert failed on $pid"
	    notice "Revert change '$pid'"
	fi
	# 6) Rename its artifacts
	if [[ "$AUTO_ADD" == true ]]; then
	    # Check if it is a new file
	    if grep -q '^--- /dev/null' "$pf"; then
		local file_to_add="$(myl_get "$metaf" 'filename')"
		if [[ -n "$file_to_add" ]]; then
		    add_file_to_session_filesets "$file_to_add" "$session"
		    notice "Added new file '$file_to_add' to active session filesets."
		fi
            fi
        fi
	if [[ "$revert" == false ]] ; then
	    change_state_for_meta applied "$metaf"
	else
	    change_state_for_meta pending "$metaf"
	fi
    done
    popd >/dev/null
}

# change_state_for_meta <new_state> <json_file> [<json_file>...]
#   For each given JSON metadata file, extract its ID (timestamp–sha–index),
#   detect its old_state (pending|applied|skipped), and then rename ALL
#   artifacts for that ID from old_state → new_state.
change_state_for_meta() {
    local new_state=$1
    shift
    (( $# >= 1 )) || die "Usage: maia change <new-state> id [...]"

    shopt -s nullglob

    trigger_event "pre-change-state-${new_state}" "$@"
    for metaf in "$@"; do
	[[ -f "$metaf" ]] || die "File not found: $metaf"
	# basename + strip extension → e.g. 20250517T191054-81610843-+-pending
	local fname=$(basename -- "$metaf")
	local base="${fname%.myl}"
	# old_state is the last dash-segment
	local old_state="$(get_status $metaf)"
	# id_with_index_state is everything before the last dash + state
	local id_with_index_state="${base%-*}"
	local id_with_index="${id_with_index_state%-${old_state}}"
	local id="${id_with_index%-+}"
	if [ "$old_state" = "$new_state" ] ; then
	    if [ "$id_with_index" = "$id" ] ; then
		notice "Sub-change $id already has state $new_state"
	    else
		notice "Change $id already has state $new_state"
	    fi
	    continue
	fi
	# now glob and rename every artifact f for this id+old_state
	for f in "$changes_dir/$session/${id_with_index_state}-${old_state}".*; do
	    [[ -f "$f" ]] || continue
	    # compute new name by swapping old_state → new_state
	    local target="${f%-${old_state}.*}-${new_state}.${f##*.}"
	    mv -- "$f" "$target"
	done
	if [ "$id_with_index" = "$id" ] ; then
            info "Marked sub-change $id as $new_state"
	else
            info "Marked change $id as $new_state"
	fi
    done
    trigger_event "post-change-state-${new_state}" "$@"
}

make_patch() {
    local fname="$1"          # relative filename in workspace (e.g., src/foo.c)
    local new_content_file="$2" # path to the new file content (in changes dir)
    local patch_file="$3"     # path to write the patch output

    # Build workspace file path
    local orig_file="$ws_root/$fname"

    # Determine source label for diff (must be /dev/null if file missing)
    local src_label
    if [[ -f "$orig_file" ]]; then
        src_label="a/$fname"
    else
        src_label="/dev/null"
        orig_file="/dev/null"
    fi

    # Generate the patch using unified diff
    local patch_text=$(diff -u --label "$src_label" --label "b/$fname" "$orig_file" "$new_content_file" 2>/dev/null) || true

    if [[ -n "$patch_text" ]]; then
        echo "$patch_text" > "$patch_file"
        notice "Generated patch file '$patch_file'"
        return 0
    else
        # No differences, remove patch file if it exists
        rm -f "$patch_file"
        notice "No differences detected; patch file removed"
        return 1
    fi
}

showfiles() {
    local prefix="$1"
    local patch=$(match_single_file "$prefix" .patch)
    local text=$(match_single_file "$prefix" .txt)
    local snippet=$(match_single_file "$prefix" .snippet)
    local shell=$(match_single_file "$prefix" .shell)
    local action=$(match_single_file "$prefix" .action)
    if [ -n "$patch" ] ; then
	echo "Suggested patch below:"
	echo "======================"
	read_file_by_line "$patch" cr
    elif [ -n "$shell" ] ; then
	local shellout=$(match_single_file "$prefix" .output)
	local shellstat=$(match_single_file "$prefix" .exit_status)
	if [ -n "$shellout" ] ; then
	    echo "Command output below:"
	    echo "====================="
	    read_file_by_line "$shellout" cr
	    echo
	    echo "Exit status below:"
	    echo "=================="
	    if [ -n "$shellstat" ] ; then
		read_file_by_line "$shellstat" cr
	    fi
	    echo
	else
	    echo "Suggested commands below:"
	    echo "========================="
	    read_file_by_line "$shell" cr
	    echo
	fi
    elif [ -n "$action" ] ; then
	local actionout=$(match_single_file "$prefix" .output)
	local actionstat=$(match_single_file "$prefix" .exit_status)
	if [ -n "$actionout" ] ; then
	    echo "Command output below:"
	    echo "====================="
	    read_file_by_line "$actionout" cr
	    echo
	    echo "Exit status below:"
	    echo "=================="
	    if [ -n "$actionstat" ] ; then
		read_file_by_line "$actionstat" cr
	    fi
	    echo
	else
	    echo "Suggested commands below:"
	    echo "========================="
	    read_file_by_line "$action" cr
	    echo
	fi
    elif [ -n "$text" ] ; then
	echo "Manual change description below:"
	echo "================================"
	read_file_by_line "$text" cr
	echo
    elif [ -n "$snippet" ] ; then
	echo "Suggested code snippet below:"
	echo "============================="
	read_file_by_line "$snippet" cr
	echo
    fi
}

handle_change_command() {
    [[ "$1" =~ ^-h|--help$ ]] && change_usage
    [[ "$2" =~ ^-h|--help$ ]] && change_usage
    cmd=$1; shift
    # Determine active session and ensure it exists
    local session=$(resolve_session_name)
    ensure_session_exists "$session"
    local session_meta=$(resolve_session_meta "$session")

    local session_ws=$(resolve_session_workspace "$session")
    validate_workspace_exists "$session_ws"

    # NOT LOCAL!
    changes_dir="$(resolve_changes_path "$session_ws")"

    # Global flags
    UPDATE_HISTORY=$(get_config prune_when_applied)
    if [ "$cmd" = "skipped" ] ; then
	UPDATE_HISTORY=$(get_config prune_when_skipped)
    fi
    DRY_RUN=false
    AUTO_ADD=$(get_config auto_add_new_files_on_apply true)
    while [[ "$1" =~ ^-- ]]; do
	case "$1" in
	    --update-history) UPDATE_HISTORY=true;  shift;;
	    --keep-history)   UPDATE_HISTORY=false; shift;;
	    --dry-run)        DRY_RUN=true;         shift;;
	    --auto-add)       AUTO_ADD=true;        shift;;
	    --no-auto-add)    AUTO_ADD=false;       shift;;
	    --session)
		shift
		session="$1"
		shift
		;;
	    *) break;;
	esac
    done

    case "$cmd" in
	list|ls)
	    # delegate to list handler; remaining args are status flags (--pending, --applied, --skipped, --all)
	    change_list "$session" "$@"
	    ;;

	save)
	    local filename="$1"
	    if [[ -z "$filename" ]] ; then
		die "Filename must be provided."
	    fi
	    if [[ -d "$filename" ]] ; then
		die "Cannot save to a directory."
	    fi
	    shift
	    id="$1"
	    shift
	    if [[ -n "$1" ]] ; then
		die "Can only save one change at a time."
	    fi
	    local prefix file
	    LC_COLLATE=C
	    shopt -s nullglob
	    prefix="$changes_dir/$session/$id-+-"
	    file=$(match_single_file "$prefix" ".myl")
	    if [[ -n "$file" ]]; then
		# It's a set id; show the set plus its sub-IDs
		die "Cannot save a change set."
	    else
		# Not a set id, fallback to normal single file display
		prefix="$changes_dir/$session/$id"
		file=$(match_single_file "$prefix" ".myl")
		if [[ -z "$file" ]] ; then
		    die "Change '$id' not found."
		fi
		local type=$(myl_get "$file" "type")
		local tosave=$(match_single_file "$prefix" ".$type")
		if [[ -n "$tosave" ]] ; then
		    notice "Change '$id' saved to '$filename'."
		    cp "$tosave" "$filename"
		else
		    die "No data of type '$type' found for change '$id'."
		fi
	    fi
	    ;;

	show)
	    raw=false
	    if [[ "$1" == "--raw" ]] ; then
		raw=true
		shift
	    fi
	    # Add ID if none specified
	    if (( $# < 1 )); then
		local xid=$(find_last_set_change_id "$session")
		[[ -n "$xid" ]] || die "No change ID found."
		set -- "$xid"
	    fi
	    id=$1; shift
	    local prefix file
	    LC_COLLATE=C
	    shopt -s nullglob
	    prefix="$changes_dir/$session/$id-+-"
	    file=$(match_single_file "$prefix" ".myl")
	    if [[ -n "$file" ]]; then
		# It's a set id; show the set plus its sub-IDs
		if $raw; then
		    cat "$prefix"*.* 2>/dev/null || die "No files for ID $id"
		    echo
		    if [[ -e "$changes_dir/$session/$id.txt" ]] ; then
			read_file_by_line "$changes_dir/$session/$id.txt" cr
		    fi
		else
		    myl_pretty "$file"
		    echo
		    showfiles "$prefix"
		    if [[ -e "$changes_dir/$session/$id.txt" ]] ; then
			echo "Assistant response text below:"
			echo "=============================="
			read_file_by_line "$changes_dir/$session/$id.txt" cr
		    fi
		fi

		# Now show all sub-IDs
		shopt -s nullglob
		local files=( "$changes_dir/$session/${id}-"[0-9]*".myl" )
		for subchange in "${files[@]}"; do
		    local subbase=$(basename "$subchange" .myl)
		    local subid="${subbase%-*}"
		    echo
		    echo "Sub-change: $subid"
		    myl_pretty "$subchange"
		    echo
		    if [[ "$raw" == false ]]; then
			local subprefix="${changes_dir}/$session/${subbase}"
			showfiles "$subprefix"
		    fi
		done
	    else
		# Not a set id, fallback to normal single file display
		prefix="$changes_dir/$session/$id"
		file=$(match_single_file "$prefix" ".myl")
		if $raw; then
		    cat "$prefix"*.* 2>/dev/null || die "No files for ID $id"
		    echo
		    if [[ -e "$changes_dir/$session/$id.txt" ]] ; then
			read_file_by_line "$changes_dir/$session/$id.txt" cr
		    fi
		else
		    [[ -f "$file" ]] || die "Change '$id' not found [$file]"
		    myl_pretty "$file"; echo
		    showfiles "$prefix"
		fi
	    fi
	    ;;

	edit)
	    # edit [--assign-path <path>] <ID> [<ID>...]
	    local assign_path=""
	    if [[ "$1" == "--assign-path" ]]; then
		shift
		assign_path="$1"
		shift
	    fi
	    # Add ID if none specified
	    if (( $# < 1 )); then
		local xid=$(find_last_set_change_id "$session")
		[[ -n "$xid" ]] || die "No change ID found."
		set -- "$xid"
	    fi

	    for id in "$@"; do
		# 1) Try to find the “set” JSON (index = +)
		prefix="$changes_dir/$session/$id-+-"
		file=$(match_single_file "$prefix" ".myl")
		# 2) Fallback to numbered JSON if no set file
		if [[ -z "$file" ]]; then
		    prefix="$changes_dir/$session/$id-"
		    file=$(match_single_file "$prefix" ".myl")
		fi
		[[ -f "$file" ]] || die "Change '$id' not found (tried '$prefix*.myl')"

		# 3) Optionally reassign path
		if [[ -n "$assign_path" ]]; then
		    myl_update "$file" "path" "$assign_path"
		    notice "Reassigned path for $id -> $assign_path"
		fi

		# 4) Launch editor
		${EDITOR:-vi} "$file"
	    done
	    ;;

	run|"do")
	    local ws_meta="$(resolve_workspace_meta)"
	    # Global root
	    local workspace_root="$(resolve_workspace_root "$ws_name")"
	    for id in "$@"; do
		if [[ "$id" =~ -[0-9][0-9]?[0-9]?$ ]]; then
		    local prefix="$changes_dir/$session/$id-"
		    local metaf=$(match_single_file "$prefix" ".myl")
		    if [[ ! -e "$metaf" ]] ; then
			warn "Metadata for sub-change $id not found, skipping."
			continue
		    fi
		    local status=$(get_status "$metaf")                 # => "pending"
		    local type=$(myl_get "$metaf" "type")
		    [[ "$status" == "pending" ]] || { notice "Skipping change '$id' since it is not 'pending'"; continue; }
		    [[ "$type"   == "shell"  || "$type" == "action" ]] || die "Cannot auto-apply non-shell '$id'"
		    change_state_for_meta "running" "$metaf"
		    # OBSERVE! Files are changed now to running!!!
		    metaf=$(match_single_file "$prefix" ".myl")
		    local shellfile="${changes_dir}/$session/${id}-running.${type}"
		    [[ -e "${shellfile}" ]] || { warn "Skipping change '$id' since it is missing a shell command file."; continue; }
		    local outputfile="${changes_dir}/$session/${id}-running.output"
		    cd "$workspace_root"
		    (
			export PS1='$ '
			export PS2='> '
			bash --noprofile --norc -i < "${shellfile}" > "$outputfile" 2>&1
		    )
		    local exit_status=$?
		    # Remove the tailing $exit from the file
		    if [[ "$(tail -n 1 "$outputfile")" == '$ exit' ]]; then
			sed -i '$d' "$outputfile"
		    fi
		    echo $exit_status > "${changes_dir}/$session/${id}-running.exit_status"
		    if [[ $exit_status == 0 ]] ; then
			change_state_for_meta "finished" "$metaf"
			post_check "$session" "${id%-*}" finished
		    else
			change_state_for_meta "failed" "$metaf"
			post_check "$session" "${id%-*}" failed
		    fi
		    # OBSERVE! Files are changed now to finished or failed!!!
		    metaf=$(match_single_file "$prefix" ".myl")
		else
		    # While change set
		    notice "$id is a change set. Execute individually instead."
		    post_check "$session" "$id" applied
		fi    
	    done
	    ;;
	
	apply|revert)
	    # apply|revert [--dry-run] [--keep-history] [--update-history] <ID> [<ID>...]
	    # Add ID if none specified
	    if (( $# < 1 )); then
		local xid=$(find_last_set_change_id "$session")
		[[ -n "$xid" ]] || die "No change ID found."
		set -- "$xid"
	    fi

	    # Determine project root
	    local ws_meta="$(resolve_workspace_meta)"
	    # Global root
	    local workspace_root="$(resolve_workspace_root "$ws_name")"
	    if [[ ! -f "$ws_meta" ]]; then
		die "No workspace in use. Create a workspace and set it as the session workspace first."
	    fi
	    for id in "$@"; do
		# If this is a sub-entry (numeric suffix), treat individually
		# We can handle up to 999 changes
		if [[ "$id" =~ -[0-9][0-9]?[0-9]?$ ]]; then
		    # --- single sub-entry ---
		    # Find its JSON metadata
		    prefix="$changes_dir/$session/$id-"
		    metaf=$(match_single_file "$prefix" ".myl")
		    if [[ ! -e "$metaf" ]] ; then
			warn "Metadata for sub-change $id not found, skipping."
			continue
		    fi
		    status=$(get_status "$metaf")                 # => "pending"
		    type=$(myl_get "$metaf" "type")
		    if [[ "$cmd" == "apply" ]] ; then
			[[ "$status" == "pending" ]] || { notice "Sub-change '$id' already in status $status"; continue; }
			[[ "$type"   == "patch"  ]] || die "Cannot auto-apply non-patch '$id'"
			apply_patch "$workspace_root" "${changes_dir}/$session/${id}-pending.patch"
			post_check "$session" "${id%-*}" applied
		    elif [[ "$cmd" == "revert" ]] ; then
			[[ "$status" == "applied" ]] || { notice "Sub-change '$id' already in status $status"; continue; }
			[[ "$type"   == "patch"  ]] || die "Cannot auto-revert non-patch '$id'"
			apply_patch -R "$workspace_root" "${changes_dir}/$session/${id}-applied.patch"
			post_check "$session" "${id%-*}" pending
		    fi
		else
		    # --- whole change set ---
		    pre_check "$session" "$id"
		    # Collect all pending patches
		    shopt -s nullglob
		    export LC_COLLATE=C
		    local subs=( "$changes_dir/$session/${id}-"*[0-9]"-"*".myl" )
		    if (( ${#subs[@]} == 0 )); then
			notice "No sub-entries found for $id"
			continue
		    fi
		    # 2) Verify no non-patch pending entries
		    bad=false
		    for jf in "${subs[@]}"; do
			status=$(get_status "$jf")
			type=$(myl_get "$jf" 'type')
			if [[ "$type" != "patch" ]] ; then
			    if [[ "$status" == "pending" && "$cmd" == "apply" ]]; then
				local subid=$(basename -- "$jf" .myl)
				subid=${subid%-pending}
				error "Cannot auto-apply: $subid is of type $type."
				bad=true
			    fi
			    if [[ "$status" == "applied" && "$cmd" == "revert" ]]; then
				local subid=$(basename -- "$jf" .myl)
				subid=${subid%-applied}
				error "Cannot auto-revert: $subid is of type $type."
				bad=true
			    fi
			fi
		    done
		    $bad && continue
		    # 3) Collect only the pending patch files
		    if [[ "$cmd" == "apply" ]] ; then
			patches=( "$changes_dir/$session/${id}-"*[0-9]"-pending.patch" )
			if (( ${#patches[@]} == 0 )); then
			    notice "No pending patches for $id"
			    continue
			fi
			apply_patch "$workspace_root" "${patches[@]}"
			change_state_for_meta applied $(match_single_file "$changes_dir/$session/${id}-+-pending.myl")
			# Change the state
			notice "Applied all patches for change set $id"
			post_check "$session" "$id" applied
		    elif [[ "$cmd" == "revert" ]] ; then
			patches=( "$changes_dir/$session/${id}-"*[0-9]"-applied.patch" )
			if (( ${#patches[@]} == 0 )); then
			    notice "No applied patches for $id"
			    continue
			fi
			apply_patch -R "$workspace_root" "${patches[@]}"
			change_state_for_meta pending $(match_single_file "$changes_dir/$session/${id}-+-applied.myl")
			# Change the state
			notice "Reverted all patches for change set $id"
			# No post check, because this is a revert: post_check "$session" "$id" pending
		    fi
		fi
	    done
	    ;;

	applied|skipped|pending|finished|failed|running)
	    # Add ID if none specified
	    if (( $# < 1 )); then
		local xid=$(find_last_set_change_id "$session")
		[[ -n "$xid" ]] || die "No change ID found."
		set -- "$xid"
	    fi
	    local action=$cmd
	    export LC_COLLATE=C
	    shopt -s nullglob
	    for id in "$@"; do
		if [[ ! "$id" =~ -[0-9][0-9]?[0-9]?$ ]]; then
		    # --- whole change set ---
		    if [[ "$action" != "pending" ]]; then
			pre_check "$session" "$id"
		    fi
		    change_state_for_meta "$action" \
					  "$changes_dir/$session/${id}-"*[0-9]"-"*".myl" \
					  $(match_single_file "$changes_dir/$session/$id-+-" ".myl")
		    notice "Updated to state '$action' for change set $id and all sub-entries."
		else
		    # --- single sub-entry ---
		    change_state_for_meta "$action" "$changes_dir/$session/${id}-"*".myl"
		    notice "Updated to state '$action' for change $id."
		fi
		if [[ ! "$id" =~ -[0-9][0-9]?[0-9]?$ && "$action" != "pending" ]]; then
		    # --- whole change set ---
		    post_check "$session" "$id" "$action"
		fi
	    done ;;

	delete)
	    local MATCH=""
	    # Parse options before IDs
	    while [[ $# -gt 0 && "$1" == --* ]]; do
		case "$1" in
		    --all) shift; MATCH="*-+-*.myl" ;;
		    *) break ;;
		esac
	    done
	    if [[ -n "$MATCH" ]] ; then
		local -a all_ids=()
		local f fname id
		for f in "$changes_dir/$session"/$MATCH; do
		    [[ -f "$f" ]] || continue
		    fname=$(basename -- "$f")
		    id=${fname%%-+-*}
		    all_ids+=( "$id" )
		done
		if [[ ${#all_ids[@]} -eq 0 ]]; then
                    notice "No changes found."
                    exit 0
                fi
		# Add all found base IDs to $@
		set -- "${all_ids[@]}"
	    fi
	    # Add ID if none specified
	    if (( $# < 1 )); then
		local xid=$(find_last_set_change_id "$session")
		[[ -n "$xid" ]] || die "No change ID found."
		set -- "$xid"
	    fi
	    for id in "$@"; do
		# Gather relevant json files
		local files=("$changes_dir/$session/$id-"*.myl)
		# Delete base and sub-entry files accordingly, including .txt files
		trigger_event "pre-change-delete" "${files[@]}"
		if [[ ! "$id" =~ -[0-9][0-9]?[0-9]?$ ]]; then
		    rm -f "$changes_dir/$session/$id-"*.* 2>/dev/null
		    rm -f "$changes_dir/$session/$id.txt" 2>/dev/null
		    rm -f "$changes_dir/$session/$id"-[0-9]*.txt 2>/dev/null
		    notice "Deleted base change $id and all its sub-entries"
		else
		    rm -f "$changes_dir/$session/$id-"*.* 2>/dev/null
		    rm -f "$changes_dir/$session/$id".txt 2>/dev/null
		    notice "Deleted change $id"
		fi
		trigger_event "post-change-delete" "${files[@]}"
	    done
	    ;;

	*) change_usage ;;
    esac
}
