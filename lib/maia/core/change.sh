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

  adjust [<ID> [<ID>...]]
    Adjust the body of the change by opening it up in an editor.
    Can be useful to remove whice-space, comments or similar that made
    further processing complicated.

  process [<ID> [<ID>...]]
    Process the body of the change similar to the 'maia parse' would have done.

  convert <ID> [--type snippet|file|shell|diff|manual] [filename]
    Change the type and/or filename of a change. Assign filename if provided.
    Automatically generates or removes patch files as needed.

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
    local root_meta="$changes_dir/$session/${idbase}-+-${state_suffix}.json"
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
    local instructions=$(< "$instructions_file")

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
    local files=( "$changes_dir"/$session/*-+-*.json )
    if (( ${#files[@]} == 0 )); then
        echo ""
        return
    fi
    # Extract IDs by stripping directory and trailing '-+.json'
    local ids=()
    for f in "${files[@]}"; do
        local fname=$(basename -- "$f")
        local id="${fname%-+-*.json}"
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
    for f in "$changes_dir/$session/${base}-"*".json"; do
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
    for f in "$changes_dir/$session/${base}-"*".json"; do
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
	for file in "$scdir"/*-${status_filter}.json; do
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
	    base="${fname%.json}"                # => "...-+-pending" or "...-0-pending"
	    status=$(get_status "$file")
	    # 3) Extract the “index” field (either "+" or a digit)
	    tmp="${base%-*}"                     # => "...-+-" or "...-0"
	    index="${tmp##*-}"                   # => "+" or "0"
	    # 4) Compute filebase = everything up to (and including) the index
	    filebase="$tmp"                      # => "2025-05-17T19:10:54-81610843-+"
            #    or "…-81610843-0"
	    type=$(jq -r '.type' "$file")
	    filename=$(jq -r '.filename' "$file")
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

change_adjust() {
    local ids=("$@")
    if (( ${#ids[@]} == 0 )); then
        local last_id=$(find_last_set_change_id "$session")
        if [[ -z "$last_id" ]]; then
            die "No change ID found."
        fi
        ids=("$last_id")
    fi

    local changes_dir="$(resolve_changes_path)"

    for id in "${ids[@]}"; do
        local body_file="$changes_dir/$session/${id}-pending.body"
        if [[ ! -f "$body_file" ]]; then
            die "Change body file not found for ID '$id' ($body_file)"
        fi
        info "Opening body file for editing: $body_file"
        "${EDITOR:-vi}" "$body_file"
    done
}

change_process() {
    local ids=("$@")
    if (( ${#ids[@]} == 0 )); then
        local last_id
        last_id=$(find_last_set_change_id "$session")
        if [[ -z "$last_id" ]]; then
            die "No change ID found."
        fi
        ids=("$last_id")
    fi

    local changes_dir="$(resolve_changes_path)"

    local ws_name=$(resolve_workspace_name)
    local ws_root=$(resolve_workspace_root "$ws_name")
    [[ -n "$ws_root" && -d "$ws_root" ]] || die "Workspace root '$ws_root' not found or invalid"

    # Pass along options for parse.pl from config
    local tab_width=$(jq -r '.tab_width // 4' <<< "$_cfg")
    local splice_allowed_files=$(jq -r '.splice_allowed_files // "\\.(?:py|c|cpp|php|js|pl|pm|sh|txt)$"' <<< "$_cfg")
    local session_name=$(resolve_session_name)

    for id in "${ids[@]}"; do
        local body_file="$changes_dir/$session/${id}-pending.body"
        if [[ ! -f "$body_file" ]]; then
            die "Change body file not found for ID '$id' ($body_file)"
        fi

        notice "Processing change ID $id"
        "$MAIA_CORE_LIB_DIR/parse.pl" process --loglevel "$TERM_LOGLEVEL" --session "$session_name" \
            --tab-width "$tab_width" --allowed-files "$splice_allowed_files" \
            "$body_file" "$ws_root"
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
    mapfile -t sess_fs < <(jq -r '.[]' <<<"$expanded_filesets_json")
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
	    local jsonf="$changes_dir/$session/${pid}-pending.json"
	    patch -p1 < "$pf" || die "Apply failed on $pid"
	    notice "Applied change '$pid'"
	else
	    pid=$(basename -- "$pf" -applied.patch)
	    local jsonf="$changes_dir/$session/${pid}-applied.json"
	    patch -R -p1 < "$pf" || die "Revert failed on $pid"
	    notice "Revert change '$pid'"
	fi
	# 6) Rename its artifacts
	if [[ "$AUTO_ADD" == true ]]; then
	    # Check if it is a new file
	    if grep -q '^--- /dev/null' "$pf"; then
		local file_to_add="$(jq -r '.filename' "$jsonf")"
		if [[ -n "$file_to_add" ]]; then
		    add_file_to_session_filesets "$file_to_add" "$session"
		    notice "Added new file '$file_to_add' to active session filesets."
		fi
            fi
        fi
	if [[ "$revert" == false ]] ; then
	    change_state_for_jsons applied "$jsonf"
	else
	    change_state_for_jsons pending "$jsonf"
	fi
    done
    popd >/dev/null
}

# change_state_for_jsons <new_state> <json_file> [<json_file>...]
#   For each given JSON metadata file, extract its ID (timestamp–sha–index),
#   detect its old_state (pending|applied|skipped), and then rename ALL
#   artifacts for that ID from old_state → new_state.
change_state_for_jsons() {
    local new_state=$1
    shift
    (( $# >= 1 )) || die "Usage: maia change <new-state> id [...]"

    shopt -s nullglob

    trigger_event "pre-change-state-${new_state}" "$@"
    for jsonf in "$@"; do
	[[ -f "$jsonf" ]] || die "File not found: $jsonf"
	# basename + strip extension → e.g. 20250517T191054-81610843-+-pending
	local fname=$(basename -- "$jsonf")
	local base="${fname%.json}"
	# old_state is the last dash-segment
	local old_state="$(get_status $jsonf)"
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

handle_change_convert() {
    local new_type=""
    local args=()

    # Parse arguments: first is ID, then options and optional filename
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                shift
                [[ -z "$1" ]] && die "Missing argument for --type"
                new_type="$1"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Extract ID and optional filename from remaining args
    local id="${args[0]}"
    local filename="${args[1]:-}"

    [[ -n "$id" ]] || die "Change ID required for convert"

    local ws_name=$(resolve_workspace_name)
    ws_root=$(resolve_workspace_root "$ws_name")
    [[ -n "$ws_root" && -d "$ws_root" ]] || die "Workspace root '$ws_root' not found or invalid"
    local changes_dir="$(resolve_changes_path)"

    # Locate metadata JSON (numbered assumed, set cannot be converted)
    local meta_path=$(find "$changes_dir/$session" -maxdepth 1 -type f -name "${id}-[a-z]*.json" | head -n1)
    [[ -n "$meta_path" && -f "$meta_path" ]] || die "Metadata JSON for ID '$id' not found"

    # If filename provided, update metadata now
    if [[ -n "$filename" ]]; then
        jq --arg fn "$filename" '.filename = $fn' "$meta_path" > "${meta_path}.tmp" && mv "${meta_path}.tmp" "$meta_path"
        notice "Assigned filename '$filename' to change '$id'"
    fi

    # Reload metadata to get current type and filename
    local curr_type=$(jq -r '.type // empty' "$meta_path")
    local curr_filename=$(jq -r '.filename // empty' "$meta_path")

    [[ -n "$curr_type" ]] || die "Change '$id' has no type in metadata"
    [[ -n "$curr_filename" ]] || die "Change '$id' has no filename assigned"

    # Determine target type if not specified
    if [[ -z "$new_type" ]]; then
        if [[ "$curr_type" == "file" || "$curr_type" == "patch" ]]; then
            new_type="snippet"
        elif [[ "$curr_type" == "snippet" ]]; then
            new_type="file"
        else
            new_type="$curr_type"
        fi
        notice "No --type specified; defaulting to '$new_type'"
    fi

    # Define suffixes for current and new types
    declare -A type_suffix=(
        [file]="file"
        [patch]="file"
        [snippet]="snippet"
        [shell]="sh"
        [diff]="diff"
        [manual]="txt"
    )
    local curr_suffix="${type_suffix[$curr_type]}"
    local new_suffix="${type_suffix[$new_type]}"

    # Possible numbered suffix from meta file name (e.g. -+ or -0)
    local idx_suffix
    if [[ "$meta_path" =~ ([^/]+)\.json$ ]]; then
        idx_suffix="${BASH_REMATCH[1]}"
    else
	die "Cannot convert a set type change."
    fi

    local body_file="${changes_dir}/$session/${idx_suffix}.body"
    # Paths to current files
    local curr_content_file="${changes_dir}/$session/$session/${idx_suffix}.${curr_suffix}"
    local curr_patch_file="${changes_dir}/$session/${idx_suffix}.patch"

    # Paths to new files
    local new_content_file="${changes_dir}/$session/${idx_suffix}.${new_suffix}"
    local new_patch_file="${changes_dir}/$session/${idx_suffix}.patch"

    # Validate content file exists
    if [[ ! -f "$curr_content_file" ]]; then
        die "Content file '$curr_content_file' not found for change '$id'"
    fi

    # Handle conversion

    # If new type is 'file', generate patch from content and workspace file
    rm -f "$curr_content_file"
    cp "$body_file" "$new_content_file"
    if [[ "$new_type" == "file" ]]; then
        # Generate patch file
        if make_patch "$curr_filename" "$new_content_file" "$new_patch_file"; then
	    new_type="patch"
	fi
    else
        if [[ -f "$curr_patch_file" ]]; then
            rm -f "$curr_patch_file"
            debug "Removed patch file '$curr_patch_file'"
        fi
    fi

    # Update metadata JSON with new type and filename
    jq --arg t "$new_type" --arg fn "$curr_filename" \
       '.type = $t | .filename = $fn' "$meta_path" > "${meta_path}.tmp" && mv "${meta_path}.tmp" "$meta_path"

    info "Converted change '$id' to type '$new_type' with filename '$curr_filename'"
}

showfiles() {
    local prefix="$1"
    local patch=$(match_single_file "$prefix" .patch)
    local text=$(match_single_file "$prefix" .txt)
    local snippet=$(match_single_file "$prefix" .snippet)
    local shell=$(match_single_file "$prefix" .shell)
    if [ -n "$patch" ] ; then
	echo "Suggested patch below:"
	echo "======================"
	cat "$patch"
    elif [ -n "$shell" ] ; then
	local shellout=$(match_single_file "$prefix" .output)
	local shellstat=$(match_single_file "$prefix" .exit_status)
	if [ -n "$shellout" ] ; then
	    echo "Command output below:"
	    echo "====================="
	    cat "$shellout"
	    echo
	    echo "Exit status below:"
	    echo "=================="
	    if [ -n "$shellstat" ] ; then
		cat "$shellstat"
	    fi
	    echo
	else
	    echo "Suggested commands below:"
	    echo "========================="
	    cat "$shell"
	    echo
	fi
    elif [ -n "$text" ] ; then
	echo "Manual change description below:"
	echo "================================"
	cat "$text"
    elif [ -n "$snippet" ] ; then
	echo "Suggested code snippet below:"
	echo "============================="
	cat "$snippet"
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
    UPDATE_HISTORY=$(jq -r '.prune_when_applied' <<< "$_cfg")
    if [ "$cmd" = "skipped" ] ; then
	UPDATE_HISTORY=$(jq -r '.prune_when_skipped' <<< "$_cfg")
    fi
    DRY_RUN=false
    AUTO_ADD=$(jq -r '.auto_add_new_files_on_apply // true' <<< "$_cfg")
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
	    file=$(match_single_file "$prefix" ".json")
	    if [[ -n "$file" ]]; then
		# It's a set id; show the set plus its sub-IDs
		if $raw; then
		    cat "$prefix"*.* 2>/dev/null || die "No files for ID $id"
		    echo
		    if [[ -e "$changes_dir/$session/$id.txt" ]] ; then
			cat "$changes_dir/$session/$id.txt"
		    fi
		else
		    jq . "$file"; echo
		    showfiles "$prefix"
		    if [[ -e "$changes_dir/$session/$id.txt" ]] ; then
			echo "Assistant response text below:"
			echo "=============================="
			cat "$changes_dir/$session/$id.txt"
		    fi
		fi

		# Now show all sub-IDs
		shopt -s nullglob
		local files=( "$changes_dir/$session/${id}-"[0-9]*".json" )
		for subjson in "${files[@]}"; do
		    local subbase=$(basename "$subjson" .json)
		    local subid="${subbase%-*}"
		    echo
		    echo "Sub-change: $subid"
		    jq . "$subjson"
		    if [[ "$raw" == false ]]; then
			local subprefix="${changes_dir}/$session/${subbase}"
			showfiles "$subprefix"
		    fi
		done
	    else
		# Not a set id, fallback to normal single file display
		prefix="$changes_dir/$session/$id"
		file=$(match_single_file "$prefix" ".json")
		if $raw; then
		    cat "$prefix"*.* 2>/dev/null || die "No files for ID $id"
		    echo
		    if [[ -e "$changes_dir/$session/$id.txt" ]] ; then
			cat "$changes_dir/$session/$id.txt"
		    fi
		else
		    [[ -f "$file" ]] || die "Change '$id' not found [$file]"
		    jq . "$file"; echo
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
		file=$(match_single_file "$prefix" ".json")
		# 2) Fallback to numbered JSON if no set file
		if [[ -z "$file" ]]; then
		    prefix="$changes_dir/$session/$id-"
		    file=$(match_single_file "$prefix" ".json")
		fi
		[[ -f "$file" ]] || die "Change '$id' not found (tried '$prefix*.json')"

		# 3) Optionally reassign path
		if [[ -n "$assign_path" ]]; then
		    jq --arg p "$assign_path" '.path = $p' "$file" > tmp.$$ && mv tmp.$$ "$file"
		    notice "Reassigned path for $id -> $assign_path"
		fi

		# 4) Launch editor
		${EDITOR:-vi} "$file"
	    done
	    ;;

	run)
	    local ws_meta="$(resolve_workspace_meta)"
	    # Global root
	    local workspace_root="$(resolve_workspace_root "$ws_name")"
	    for id in "$@"; do
		if [[ "$id" =~ -[0-9][0-9]?[0-9]?$ ]]; then
		    local prefix="$changes_dir/$session/$id-"
		    local jsonf=$(match_single_file "$prefix" ".json")
		    if [[ ! -e "$jsonf" ]] ; then
			warn "Metadata for sub-change $id not found, skipping."
			continue
		    fi
		    local status=$(get_status "$jsonf")                 # => "pending"
		    local type=$(jq -r '.type'   "$jsonf")
		    [[ "$status" == "pending" ]] || { notice "Skipping change '$id' since it is not 'pending'"; continue; }
		    [[ "$type"   == "shell"  ]] || die "Cannot auto-apply non-shell '$id'"
		    change_state_for_jsons "running" "$jsonf"
		    # OBSERVE! Files are changed now to running!!!
		    jsonf=$(match_single_file "$prefix" ".json")
		    local shellfile="${changes_dir}/$session/${id}-running.shell"
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
			change_state_for_jsons "finished" "$jsonf"
		    else
			change_state_for_jsons "failed" "$jsonf"
		    fi
		    # OBSERVE! Files are changed now to finished or failed!!!
		    jsonf=$(match_single_file "$prefix" ".json")
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
		    jsonf=$(match_single_file "$prefix" ".json")
		    if [[ ! -e "$jsonf" ]] ; then
			warn "Metadata for sub-change $id not found, skipping."
			continue
		    fi
		    status=$(get_status "$jsonf")                 # => "pending"
		    type=$(jq -r '.type'   "$jsonf")
		    if [[ "$cmd" == "apply" ]] ; then
			[[ "$status" == "pending" ]] || { notice "Sub-change '$id' already in status $status"; continue; }
			[[ "$type"   == "patch"  ]] || die "Cannot auto-apply non-patch '$id'"
			apply_patch "$workspace_root" "${changes_dir}/$session/${id}-pending.patch"
		    elif [[ "$cmd" == "revert" ]] ; then
			[[ "$status" == "applied" ]] || { notice "Sub-change '$id' already in status $status"; continue; }
			[[ "$type"   == "patch"  ]] || die "Cannot auto-revert non-patch '$id'"
			apply_patch -R "$workspace_root" "${changes_dir}/$session/${id}-applied.patch"
		    fi
		else
		    # --- whole change set ---
		    pre_check "$session" "$id"
		    # Collect all pending patches
		    shopt -s nullglob
		    export LC_COLLATE=C
		    local subs=( "$changes_dir/$session/${id}-"*[0-9]"-"*".json" )
		    if (( ${#subs[@]} == 0 )); then
			notice "No sub-entries found for $id"
			continue
		    fi
		    # 2) Verify no non-patch pending entries
		    bad=false
		    for jf in "${subs[@]}"; do
			status=$(get_status "$jf")
			type=$(jq -r '.type' "$jf")
			if [[ "$type" != "patch" ]] ; then
			    if [[ "$status" == "pending" && "$cmd" == "apply" ]]; then
				local subid=$(basename -- "$jf" .json)
				subid=${subid%-pending}
				error "Cannot auto-apply: $subid is of type $type."
				bad=true
			    fi
			    if [[ "$status" == "applied" && "$cmd" == "revert" ]]; then
				local subid=$(basename -- "$jf" .json)
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
			change_state_for_jsons applied $(match_single_file "$changes_dir/$session/${id}-+-pending.json")
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
			change_state_for_jsons pending $(match_single_file "$changes_dir/$session/${id}-+-applied.json")
			# Change the state
			notice "Reverted all patches for change set $id"
			# No post check, because this is a revert: post_check "$session" "$id" pending
		    fi
		fi
	    done
	    ;;

	convert)
	    handle_change_convert "$@"
	    ;;

	adjust)
	    change_adjust "$@"
	    ;;

	process)
	    change_process "$@"
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
		    change_state_for_jsons "$action" "$changes_dir/$session/${id}-"*[0-9]"-"*".json" $(match_single_file "$changes_dir/$session/$id-+-" ".json")
		else
		    # --- single sub-entry ---
		    change_state_for_jsons "$action" "$changes_dir/$session/${id}-"*".json"
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
		    --all) shift; MATCH="*-+-*" ;;
		    *) break ;;
		esac
	    done
	    if [[ -n "$MATCH" ]] ; then
		local add_ids
		mapfile -t all_ids < <(ls "$changes_dir/$session"/$MATCH.json 2>/dev/null | xargs -n1 basename | sed -E 's/-\+-.*//')
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
		local json_files=( "$changes_dir/$session/$id"*".json" )
		# Delete base and sub-entry files accordingly, including .txt files
		if [[ ! "$id" =~ -[0-9][0-9]?[0-9]?$ ]]; then
		    trigger_event "pre-change-delete" "$changes_dir/$session/$id-"*.json
		    rm -f "$changes_dir/$session/$id-"*.* 2>/dev/null
		    rm -f "$changes_dir/$session/$id.txt" 2>/dev/null
		    rm -f "$changes_dir/$session/$id"-[0-9]*.txt 2>/dev/null
		    notice "Deleted base change $id and all its sub-entries"
		else
		    trigger_event "pre-change-delete" "$changes_dir/$session/$id-"*.json
		    rm -f "$changes_dir/$session/$id-"*.* 2>/dev/null
		    rm -f "$changes_dir/$session/$id".txt 2>/dev/null
		    notice "Deleted change $id"
		fi
	    done
	    ;;

	*) change_usage ;;
    esac
}
