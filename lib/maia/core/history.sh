#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

history_usage() {
    cat <<'EOF'
USAGE

  maia history [OPTIONS] <subcommand> [ARGS...]
  maia history [ARGS...]

Manage and manipulate the command history.

COMMANDS

  show [options] [--assistant|--tool|--user] [<range>...]
    Display entries in the given range(s), filtered by role(s).

  pop [options] [<n>]
    Remove & print last n entries (default 1).

  top [options] [<n>]
    Remove & print first n entries (default 1).

  delete [<range>...]
    Delete entries in n–m inclusive for all given ranges.

  prune [--assistant|--tool|--user] [--reduce|--edit|--cut] [<range>...]
    Prune history entries by role and mode.

  search [options] <keyword>
    Find entries containing keyword.

  clear
    Wipe the active history.

OPTIONS

  -h, --help
    Show this help message and exit.

  -a, --assistant
    Filter or prune assistant messages only.

  -t, --tool
    Filter or prune tool messages only.

  -u, --user
    Filter or prune user messages only.

  If multiple role flags are provided, pruning will error.

  --reduce
    Replace large blocks with a placeholder during pruning.

  --edit
    Edit messages in an editor during pruning.

  --cut
    Replace entire message with a placeholder during pruning.

  --raw, --json
    Print in json format. Applicable to show, search, pop and top.

EXAMPLES

    maia history prune --assistant --reduce 0-10 12 15-20
      Prune assistant messages in specified ranges by reducing content.

    maia history prune --tool --cut last
      Cut tool messages in the last entry.

    maia history prune --user --edit
      Edit user messages in the full history.

NOTES

  Range syntax:
    n-m       entries n through m (inclusive)
    n-        entries n through end
    -n        first (n+1) entries
    n         entry n (same as n-n)
    - or ""   the entire history
    last      the last entry
    last-1    the 2 last entries
    all       the entire history

  Role flags specify which type of entries to prune.
  Pruning modes differ per role (see documentation).
  Multiple ranges can be specified for batch pruning.

EOF
    exit 0
}

# Global readonly variable for jq filter to add indexes
readonly jq_add_indexes='
  [ foreach .[] as $item (
      { index: -1, user: 0, assistant: 0, tool: 0 };
      .index += 1
      | {
          value: $item,
          index: (.index),
          user_index: (if $item.role == "user" then .user else null end),
          assistant_index: (if $item.role == "assistant" then .assistant else null end),
          tool_index: (if $item.role == "tool" then .tool else null end),
          user: (if $item.role == "user" then .user + 1 else .user end),
          assistant: (if $item.role == "assistant" then .assistant + 1 else .assistant end),
          tool: (if $item.role == "tool" then .tool + 1 else .tool end)
        }
    ) ]
  | map(
      .value
      + { index: .index }
      + (if .value.role == "user" then { user_index: .user_index }
         elif .value.role == "assistant" then { assistant_index: .assistant_index }
         elif .value.role == "tool" then { tool_index: .tool_index }
         else {} end)
    )
'

prune_content() {
    local content="$1" idx="$2"
    # Call prune.pl with idx as argument, pass content via stdin, capture output
    printf '%s' "$content" | "$MAIA_CORE_LIB_DIR/prune.pl" "$idx"
}

add_original_reference() {
    local content="$1"
    local prune_id="$2"
    local marker="<<Original text reference: $prune_id>>"

    if [[ "$content" != *"$marker"* ]]; then
        content="${content}\n${marker}"
    fi
    echo -e "$content"
}

history_prune() {
    local role=""
    local -a ranges=()

    # Default mode from config
    local mode=$(jq -r '.prune_mode' <<<"$_cfg")

    # Parse flags before ranges
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assistant|--tool|--user)
                if [[ -n "$role" ]]; then
                    die "Only one of --assistant, --tool, or --user can be specified."
                fi
                role="${1#--}"
                shift
                ;;
            --reduce|--edit|--cut)
                mode="${1#--}"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done

    # If no role specified, default to assistant
    if [[ -z "$role" ]]; then
        role="assistant"
    fi

    # Collect all positional range arguments
    while [[ $# -gt 0 ]]; do
        ranges+=("$1")
        shift
    done

    # Default single range if none given
    if (( ${#ranges[@]} == 0 )); then
        ranges+=("last")
    fi

    local history_file="$(resolve_history_meta)"

    acquire_lock "${history_file}.lock"
    # Load full history with indexes
    local history_json=$(jq "$jq_add_indexes" "$history_file")

    # We work on a temporary file with indexes present

    # For each range, process pruning
    local tmpfile=$(mktemp)
    echo "$history_json" > "$tmpfile"
    local range
    for range in "${ranges[@]}"; do
        local jq_slice=$(range_defaults "$range")
        # Select entries in range and role
	local entries=$(jq --arg role "$role" '
	   map(select(.role == $role)) | .['"$jq_slice"']
	   ' "$tmpfile")
        local count=$(jq 'length' <<<"$entries")
        if [[ $count == 0 ]]; then
            info "No entries of role '$role' in range '$range' to prune."
            continue
        fi
	# Make a backup of all potentially updated entries
	json_modify "$tmpfile" '
	  . as $history
	  | ($history
	      | map(select(.role == "'"$role"'"))
	      | .['"$jq_slice"']
	      | map(.index)
	    ) as $indexes
	  | $history
	  | map(
	      .index as $index |
	      if ($indexes | index($index)) != null and (has("backup") | not) then
	        .backup = (
		  {}
		  + (if has("content") then {content: .content} else {} end)
		  + (if has("tool_calls") then {tool_calls: .tool_calls} else {} end)
		)
	      else
	        .
	      end
	    )
	    '

	local i=0
        for (( i=0; i < count; i++ )); do
            local ts=$(jq -r ".[$i].timestamp" <<<"$entries")
            local id=$(jq -r ".[$i].id" <<<"$entries")
            local prune_id="${ts}-${id}"

            # Backup original if not already backed up
	    local mapselect="map(select(.${role}_index == $i))"
            local orig_content=$(jq -r "$mapselect | .[0].content" "$tmpfile")
	    if [[ "$orig_content" == "null" ]] ; then
		orig_content=""
	    fi
            local orig_tool_calls=$(jq -r "$mapselect | .[0].tool_calls" "$tmpfile")
	    if [[ "$orig_tool_calls" == "null" ]] ; then
		orig_tool_calls=""
	    fi
	    local new_content="$orig_content"
	    local new_tool_calls="$orig_tool_calls"

            if [[ "$mode" == "cut" ]]; then
                # Cut mode replaces content and/or tool_calls accordingly
                if [[ -n "$orig_content" ]]; then
                    # Replace content with prune placeholder including prune_id
		    new_content="<<Pruned>>\n"
                fi
                if [[ -n "$orig_tool_calls" ]]; then
                    # Remove tool_calls completely
                    # If no content, add prune placeholder to content to indicate pruning
		    new_content="$new_content<<Pruned tool_calls>>"
		fi
		# For explanation see reduce case below
		if (( ${#orig_content} + 64 + ${#orig_tool_calls} < ${#new_content} + ${#new_tool_calls} )); then
		    # Restore because the pruning information is larger than the original
		    new_content="$orig_content"
		    new_tool_calls="$orig_tool_calls"
		elif [[ -n "$orig_tool_calls" ]]; then
		    # Delete the tool_calls first before we update the message
		    json_modify "$tmpfile" "map(if ${role}_index == $i then del(.tool_calls) else . end)"
                fi
            elif [[ "$mode" == "edit" ]]; then
                # Edit mode: open editor for content and tool_calls separately if present
                local edit_tmp=$(mktemp)
		local editor="${MAIA_EDITOR:-${EDITOR:-vi}}"
                if [[ -n "$orig_content" ]]; then
                    local edit_tmp=$(mktemp)
                    printf '%s' "$orig_content" > "$edit_tmp"
		    # TODO, allow either MAIA_EDITOR or EDITOR
                    "$editor" "$edit_tmp"
                    local new_content=$(cat "$edit_tmp")
                fi
                if [[ -n "$orig_tool_calls" ]]; then
                    printf '%s' "$orig_tool_calls" > "$edit_tmp"
		    # TODO, allow either MAIA_EDITOR or EDITOR
                    "$editor" "$edit_tmp"
                    local new_tool_calls=$(cat "$edit_tmp")
                fi
                rm -f "$edit_tmp"
            elif [[ "$mode" == "reduce" ]]; then
                # Reduce mode:
                # - For content: prune large blocks using prune_content()
                # - For tool_calls (only for assistant role): remove arguments for each function call, keep function names and IDs
                if [[ "$role" == "assistant" && -n "$orig_content" ]] ; then
                    new_content=$(prune_content "$orig_content" "$i")
                fi
                if [[ "$role" == "assistant" && -n "$orig_tool_calls" ]] ; then
		    # If the string is less than 16 chacters there is no point to prune because the
		    # prune information is larger.
		    # <<Original text reference: 20260818T100213-db222f2e>> + <<Pruned>>
                    local new_tool_calls="$(jq '
		      map(
		        if ((.function.arguments // "") | length) > 64
			then
			  .function.arguments = "<<Pruned>>"
			else
			  .
			end
		      )
		      ' <<<"$orig_tool_calls")"
                fi
                if [[ "$role" == "tool" ]] ; then
		    new_content="<<Pruned>>"
		fi
		# Reduce for user does nothing
		# NOTE. We should not do this generally unless we get rid of the del call above
		# 55 is the length of <<Original text reference: 20260818T100213-47388249>> (#54) + two \n
		# We select a few more because it can be worth to keep history in slightly more casese when the
		# pruning gain is really small.
		if (( ${#orig_content} + 64 + ${#orig_tool_calls} < ${#new_content} + ${#new_tool_calls} )); then
		    # Restore because the pruning information is larger than the original
		    new_content="$orig_content"
		    new_tool_calls="$orig_tool_calls"
		fi
            else
                die "Unknown prune mode: '$mode'. Valid modes are reduce, edit, cut."
            fi
	    if [[ "$orig_content" != "$new_content" || "$orig_tool_calls" != "$new_tool_calls" ]] ; then
		new_content=$(add_original_reference "$new_content" "$prune_id")
	    fi
	    # Now it is time to update
	    if [[ "$orig_content" != "$new_content" ]] ; then
		json_modify "$tmpfile" --arg content "$new_content" \
		   "map(if .role == \"$role\" and .${role}_index == $i then .content = \$content else . end)"
	    fi
	    if [[ "$orig_tool_calls" != "$new_tool_calls" ]] ; then
		json_modify "$tmpfile" --arg tool_calls "$new_tool_calls" \
		   "map(if .role == \"$role\" and .${role}_index == $i then .tool_calls = \$tool_calls else . end)"
	    fi
        done

    done

    # Write final updated history
    jq 'map(del(.index, .user_index, .assistant_index, .tool_index))' "$tmpfile" > "$history_file"
    rm -f "$tmpfile"
    release_lock "${history_file}.lock"
    info "Pruning done for role '$role' in ranges: ${ranges[*]} with mode '$mode'."
}


handle_history_command() {
    # 1) Help wins
    [[ "$1" =~ ^-h|--help$ ]] && history_usage
    [[ "$2" =~ ^-h|--help$ ]] && history_usage
    local history_dir=$(resolve_session_base)
    local history_name=$(resolve_session_name)  # Resolve the active history name using `used`
    local history_file="$(resolve_history_meta)"
    ensure_session_exists
    ensure_history_exists "$history_file"

    local cmd="${1:-}"
    case "$cmd" in
	# No arguments passed → Default to "show" behavior
	"")
	    handle_history_command show last # Show last entry
	    ;;

	show)
	    shift
	    # if no argument or an explicit empty-string is given, treat it like no-arg
	    local range="" user_only=0 assistant_only=0 raw_output=0
	    # parse all args
	    for arg in "$@"; do
		case "$arg" in
		    -u|--user)       user_only=1         ;;
		    -a|--assistant)  assistant_only=1    ;;
		    --raw|--json)    raw_output=1 ;;
		    # detect any range-like token
		    last|last-*|all) range="$arg" ;;
		    -|[0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]|*-[0-9]*|[0-9]*-[0-9]*|[0-9]*-) range="$arg" ;;
		    *)
			die "Unknown argument '$arg'."
		    ;;
		esac
	    done
	    # default range to "last" if none provided
	    [[ -z "$range" ]] && range="last"
	    # Get entries using unified function
	    local entries=$(get_history_entries "$range" "$user_only" "$assistant_only")
	    if (( raw_output )); then
		# Raw JSON output: print full JSON array
		printf '%s\n' "$entries"
	    else
		# Human-readable output: print formatted entries
		printf '%s\n' "$entries" | print_history_entries
	    fi
	    ;;

	pop)
	    shift
	    local raw_output=0
	    local n=1
	    for arg in "$@"; do
		case "$arg" in
		    --raw|--json) raw_output=1 ;;
		    *)
			if [[ "$arg" =~ ^[0-9]+$ ]]; then
			    n="$arg"
			else
			    die "Invalid argument for pop: '$arg'"
			fi
			;;
		esac
	    done
	    local total=$(jq 'length' "$history_file")
	    # If total is zero, nothing to pop; just print info and return
	    if (( total == 0 )); then
		notice "Nothing to pop from history '$history_name' (history is empty)."
		return
	    fi
	    if (( n > total )); then
		n=$total
		notice "Asked to pop more entries than what is in history. Popping $n entries."
	    fi
	    # If n is zero, nothing to pop
	    if (( n == 0 )); then
		return
	    fi
	    # Get last n entries using get_history_entries with range "-$((n-1))"
	    # Range syntax: last is last entry, last-1 is last two entries, etc.
	    local range="last-$((n-1))"
	    local entries=$(get_history_entries "$range" 0 0)
	    if (( raw_output )); then
		printf '%s\n' "$entries"
	    else
		printf '%s\n' "$entries" | print_history_entries
	    fi
	    # Remove last n entries
	    local tmp=$(mktemp)
	    exclusive_json_modify "$history_file" ".[0: -$n]"
	    info "Popped the last $n entr$([ "$n" -eq 1 ] && echo "y" || echo "ies") from history '$history_name'."
	    ;;

	top)
	    shift
	    local raw_output=0
	    local n=1
	    for arg in "$@"; do
		case "$arg" in
		    --raw|--json) raw_output=1 ;;
		    *)
			if [[ "$arg" =~ ^[0-9]+$ ]]; then
			    n="$arg"
			else
			    die "Invalid argument for top: '$arg'"
			fi
			;;
		esac
	    done
	    local total=$(jq 'length' "$history_file")
	    # If total is zero, nothing to top; just print info and return
	    if (( total == 0 )); then
		notice "Nothing to top from history '$history_name' (history is empty)."
		return
	    fi
	    if (( n > total )); then
		notice "Asked to top more entries than what is in history. Topping $n entries."
		n=$total
	    fi
	    # If n is zero, nothing to top
	    if (( n == 0 )); then
		return
	    fi
	    # Get first n entries using get_history_entries range "0-$((n-1))"
	    local range="0-$((n-1))"
	    local entries=$(get_history_entries "$range")
	    if (( raw_output )); then
		printf '%s\n' "$entries"
	    else
		printf '%s\n' "$entries" | print_history_entries
	    fi
	    # Remove first n entries
	    local tmp=$(mktemp)
	    exclusive_json_modify "$history_file" ".[ $n :]"
	    info "Popped the first $n entr$([ "$n" -eq 1 ] && echo "y" || echo "ies") from history '$history_name'."
	    ;;

        delete)
	    shift
	    local slice=$(range_defaults "${1:-}")
	    exclusive_json_modify "$history_file" "del(.[${slice}])"
	    info "Entries deleted from history '$history_name'."
	    ;;

	prune)
	    shift
	    history_prune "$@"
	    ;;

	search)
	    shift
	    # if no argument or an explicit empty-string is given, treat it like no-arg
	    local user_only=0 assistant_only=0 raw_output=0
	    # parse all args
	    for arg in "$@"; do
		case "$arg" in
		    -u|--user)       user_only=1         ;;
		    -a|--assistant)  assistant_only=1    ;;
		    --raw|--json)    raw_output=1 ;;
		    *) ;;
		esac
	    done
	    local keyword="$1"
            # Filter entries that contain keyword (case-insensitive) in any string field (tostring)
            # We want to keep all entries to preserve indexes, so we mark matches and then filter in bash
            local all_entries=$(get_history_entries "-" $user_only $assistant_only)
            # Filter entries containing keyword (case-insensitive)
            local entries=$(jq --arg kw "$keyword" '[.[] | select(tostring | test($kw; "i"))]' <<< "$all_entries")
	    if (( raw_output )); then
		# Raw JSON output: print full JSON array
		printf '%s\n' "$entries"
	    else
		# Human-readable output: print formatted entries
		printf '%s\n' "$entries" | print_history_entries
	    fi
	    ;;

	clear)
	    shift
	    acquire_lock "${history_file}.lock"
	    echo "[]" > "$history_file"  # Clear the entire history file
	    release_lock "${history_file}.lock"
	    info "History '$history_name' cleared."
	    ;;

	*)
	    handle_history_command show "$@"
	    ;;
    esac
}

get_history_entries() {
    local range="${1:-"-"}"
    local user_only="${2:-0}"
    local assistant_only="${3:-0}"

    local slice=$(range_defaults "$range")
    local role_filter
    if (( user_only && ! assistant_only )); then
        role_filter="map(select(.role == \"user\"))"
    elif (( assistant_only && ! user_only )); then
        role_filter="map(select(.role == \"assistant\"))"
    else
        role_filter="."
    fi

    local jq_filter="${jq_add_indexes} | ${role_filter} | .[${slice}]"

    local history_file="$(resolve_history_meta)"

    jq "${jq_filter}" "$history_file"
}

# Function to print multiple history entries in formatted style
print_history_entries() {
    local idx role user_idx assistant_idx ts id toolid content_b64 func_call_b64 func_call_json func_name func_args
    jq -r '.[] | [
        (.index | tostring),
        .role,
        (.user_index // 0),
        (.assistant_index // 0),
        (.tool_index // 0),
        .timestamp,
        (.id // 0),
	(.tool_call_id // "-"),
        (.content | @base64),
        ((.tool_calls // "") | @base64)
    ] | @tsv' | while IFS=$'\t' read -r idx role user_idx assistant_idx tool_idx ts id toolid content_b64 tools_call_b64; do
        content=$(echo "$content_b64" | base64 --decode)
        # Replace null content with empty string
        if [[ "$content" == "null" ]] || [[ -z "$content" ]]; then
            content=""
        fi
        if [[ "$toolid" == "-" ]] || [[ -z "$toolid" ]]; then
            toolid=""
        fi

	tools_call_json=$(echo "$tools_call_b64" | base64 --decode)
        if [[ "$tools_call_json" == "null" ]] || [[ -z "$tools_call_json" ]]; then
            tools_call_json=""
        fi

        if [[ "$role" == "user" ]]; then
            role_idx="$user_idx"
        elif [[ "$role" == "assistant" ]]; then
            role_idx="$assistant_idx"
        elif [[ "$role" == "tool" ]]; then
            role_idx="$tool_idx"
        else
            role_idx=""
        fi

	pr='[%d] %s#%s %s-%s\n'
	if [[ -n "$toolid" ]] ; then
	    pr='[%d] %s#%s %s-%s %s\n'
	fi
        printf "$pr" "$idx" "$role" "$role_idx" "$ts" "$id" $toolid
	if [[ -z "$toolid" ]] ; then
            echo '----------------------------------------'
	else
            echo '-------------------------------------------------'
	fi
        printf '%s\n\n' "$content"

        # If assistant message has function_call, print it visibly
	if [[ "$role" == "assistant" && -n "$tools_call_json" && "$tools_call_json" != "null" ]]; then
	    while IFS= read -r tool_call; do
		id=$(jq -r '.id // empty' <<<"$tool_call")
		func_name=$(jq -r '.function.name // empty' <<<"$tool_call")
		func_args=$(jq -r '.function.arguments // empty' <<<"$tool_call")

		if [[ -n "$func_name" ]]; then
		    echo "[tool call] $id $func_name($func_args)"
		    echo
		fi
	    done < <(jq -c '.[]' <<<"$tools_call_json")
	fi

    done
}
