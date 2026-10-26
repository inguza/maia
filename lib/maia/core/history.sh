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

  show [options] [show-role-options] [<range>]
    Display entries in the given range, filtered by role(s).

  pop [options] [<n>]
    Remove & print last n entries (default 1).

  top [options] [<n>]
    Remove & print first n entries (default 1).

  delete [<range>]
    Delete entries in n–m inclusive for given range.

  hide [<range>]
    Hide entries in n–m inclusive for given range.

  unhide [<range>]
    Make entries in n–m inclusive for given range.

  replace <index>
    Replace the content of one history entry. Replacement content is read from stdin.

  prune [role-option] [--reduce|--edit|--cut] [<role range>...]
    Prune history entries by role and mode.

    NOTE! If role-option is not specified, --assistant is assumed.
    NOTE! If range is omitted, last entry of the selected role is pruned.

  restore
    Restore the entry as it was before it was pruned. Will also unhide it.

  search [show-role-options] [options] <keyword>
    Find entries containing keyword.

  summarize|compact
    Summarize the whole conversation history. The whole history will replaced
    by a summary request and an assistant response containing the summary.

  verify
    Verify that the history content is correct. Will print problematic entries.

  repair
    Repair incorrect history entries.

  clear
    Wipe the active history.

OPTIONS

  -h, --help
    Show this help message and exit.

  --cut
    Replace entire message with a placeholder during pruning.

  --edit
    Edit messages in an editor during pruning.

  --reduce
    Replace large blocks with a placeholder during pruning.

  --raw, --json
    Print in json format. Applicable to show, search, pop and top.

  Show role options:

  -a, --assistant
    Assistant messages only.

  -u, --user
    User messages only.

  Role options:

  -a, --assistant, -u, --user
    See show role options above.

  -t, --tool
    Tool messages only.

  -r, --reasoning
    Reasoning messages only.

  If multiple role flags are provided, pruning will error.

EXAMPLES

    maia history prune --assistant --reduce 0-10 12 15-20
      Prune assistant messages in specified ranges by reducing content.

    maia history prune --tool --cut last
      Cut tool messages in the last entry.

    maia history prune --user --edit
      Edit last user message in the full history.

    maia history summarize

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
    prompt    the last user input
    turn      entries from last user input to the end

  Role flags specify which type of entries to operate on.
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
          reasoning_index: (if $item.role == "reasoning" then .reasoning else null end),
          user: (if $item.role == "user" then .user + 1 else .user end),
          assistant: (if $item.role == "assistant" then .assistant + 1 else .assistant end),
          tool: (if $item.role == "tool" then .tool + 1 else .tool end),
          reasoning: (if $item.role == "reasoning" then .reasoning + 1 else .reasoning end)
        }
    ) ]
  | map(
      .value
      + { index: .index }
      + (if .value.role == "user" then { user_index: .user_index }
         elif .value.role == "assistant" then { assistant_index: .assistant_index }
         elif .value.role == "tool" then { tool_index: .tool_index }
         elif .value.role == "reasoning" then { reasoning_index: .reasoning_index }
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

# Apply hide, unhide, and delete actions without leaving a visible tool result
# separated from its assistant tool call. The selected range is evaluated
# against indexed history, then the update is committed under the history lock.
history_update_tool_relationships() {
    local history_file="$1" action="$2" raw_range="$3"
    local slice
    slice="$(range_defaults "$raw_range")"

    acquire_lock "${history_file}.lock" ""
    local indexed_history
    if ! indexed_history="$(jq "$jq_add_indexes" "$history_file")"; then
        release_lock "${history_file}.lock"
        return 1
    fi

    local selected_indexes
    if ! selected_indexes="$(jq "[.[${slice}][] | .index]" <<<"$indexed_history")"; then
        release_lock "${history_file}.lock"
        return 1
    fi

    local selected_call_ids
    if ! selected_call_ids="$(jq --argjson indexes "$selected_indexes" '
        . as $messages
        | [ $indexes[] as $index
            | $messages[$index]
            | select(.role == "assistant")
            | .tool_calls[]?.id
            | select(type == "string" and length > 0)
          ]
        | unique
    ' <<<"$indexed_history")"; then
        release_lock "${history_file}.lock"
        return 1
    fi

    if [[ "$action" == "unhide" ]]; then
        local missing_call_results
        if ! missing_call_results="$(jq --argjson indexes "$selected_indexes" '
            . as $messages
            | [ $indexes[] as $index
                | $messages[$index] as $assistant
                | select($assistant.role == "assistant"
                         and ($assistant.tool_calls? | type) == "array")
                | $assistant.tool_calls[] as $call
                | select(
                    [ $messages[($index + 1):][]
                      | select(.role == "tool" and .tool_call_id == $call.id)
                    ] | length == 0
                  )
              ]
            | length > 0
        ' <<<"$indexed_history")"; then
            release_lock "${history_file}.lock"
            return 1
        fi
        if [[ "$missing_call_results" == "true" ]]; then
            warn "Cannot unhide this assistant response: one or more tool results are missing or deleted."
            release_lock "${history_file}.lock"
            return 1
        fi
    fi

    local blocked
    if ! blocked="$(jq --arg action "$action" \
        --argjson indexes "$selected_indexes" \
        --argjson call_ids "$selected_call_ids" '
        . as $messages
        | [ $indexes[] as $index
            | $messages[$index] as $item
            | select($item.role == "tool")
            | $item.tool_call_id as $call_id
            | [ $messages[]
                | select(.role == "assistant"
                         and any(.tool_calls[]?; .id == $call_id))
              ] as $parents
            | if $action == "unhide" then
                select(($parents | length) == 0
                       or (([$parents[] | select(.hidden != true)] | length) == 0
                           and (($call_ids | index($call_id)) == null)))
              else
                select(($parents | length) > 0
                       and (($call_ids | index($call_id)) == null))
              end
          ]
        | length > 0
    ' <<<"$indexed_history")"; then
        release_lock "${history_file}.lock"
        return 1
    fi

    if [[ "$blocked" == "true" ]]; then
        case "$action" in
            hide)
                warn "Cannot hide a tool result while its assistant tool call remains in history. Hide the assistant entry instead."
                ;;
            delete)
                warn "Cannot delete a tool result while its assistant tool call remains in history. Delete the assistant entry instead."
                ;;
            unhide)
                warn "Cannot unhide a tool result unless its matching assistant tool call is visible or included in the same unhide range."
                ;;
        esac
        release_lock "${history_file}.lock"
        return 1
    fi

    local status=0
    json_modify "$history_file" \
        --arg action "$action" \
        --argjson indexes "$selected_indexes" \
        --argjson call_ids "$selected_call_ids" '
        to_entries
        | map(
            .key as $index
            | .value as $item
            | (($indexes | index($index)) != null) as $selected
            | if $action == "hide" then
                if $selected
                   or ($item.role == "tool"
                       and ($call_ids | index($item.tool_call_id)) != null)
                then
                    $item + {hidden: true}
                else
                    $item
                end
              elif $action == "unhide" then
                if $selected
                   or ($item.role == "tool"
                       and ($call_ids | index($item.tool_call_id)) != null)
                then
                    $item | del(.hidden)
                else
                    $item
                end
              elif $selected then
                empty
              elif $item.role == "tool"
                   and ($call_ids | index($item.tool_call_id)) != null
              then
                    $item + {hidden: true}
              else
                    $item
              end
        )
    ' || status=$?
    release_lock "${history_file}.lock"
    return "$status"
}

history_restore_range() {
    local history_file="$1" raw_range="$2"
    local slice
    slice="$(range_defaults "$raw_range")"

    acquire_lock "${history_file}.lock" ""
    local indexed_history
    if ! indexed_history="$(jq "$jq_add_indexes" "$history_file")"; then
        release_lock "${history_file}.lock"
        return 1
    fi

    local selected_indexes
    if ! selected_indexes="$(jq "[.[${slice}][] | .index]" <<<"$indexed_history")"; then
        release_lock "${history_file}.lock"
        return 1
    fi

    local restore_filter='
        . as $history
        | ([ $indexes[] as $index
             | $history[$index]
             | select(has("backup") and (.backup.tool_calls? | type) == "array")
             | .backup.tool_calls[]?.id
             | select(type == "string" and length > 0)
           ] | unique) as $restored_tool_call_ids
        | to_entries
        | map(
            .key as $index
            | .value as $item
            | if (($indexes | index($index)) != null) and ($item | has("backup")) then
                ($item
                 | if .backup | has("content") then .content = .backup.content else . end
                 | if .backup | has("tool_calls") then .tool_calls = .backup.tool_calls else . end
                 | if .backup | has("data") then .data = .backup.data else . end
                 | if .call_pruned == true then
                     del(.summarized)
                   else
                     del(.hidden, .summarized, .call_pruned)
                   end)
              else
                $item
              end
          )
        | map(
            if .role == "tool"
               and (.tool_call_id as $id | ($restored_tool_call_ids | index($id)) != null)
            then del(.hidden, .call_pruned)
            else .
            end
          )
    '

    local prospective
    if ! prospective="$(jq --argjson indexes "$selected_indexes" "$restore_filter" <<<"$indexed_history")"; then
        release_lock "${history_file}.lock"
        return 1
    fi

    local before_issues after_issues
    if ! before_issues="$(jq -f "$MAIA_CORE_LIB_DIR/history-verify.jq" <<<"$indexed_history" | jq -S -s 'sort_by(.problem, .timestamp, .id, .tool_call_id)')" ||
       ! after_issues="$(jq -f "$MAIA_CORE_LIB_DIR/history-verify.jq" <<<"$prospective" | jq -S -s 'sort_by(.problem, .timestamp, .id, .tool_call_id)')"; then
        release_lock "${history_file}.lock"
        return 1
    fi
    if [[ "$before_issues" != "$after_issues" ]]; then
        warn "Cannot restore these entries: the restore would leave an assistant tool call without a later result, or a tool result without a visible call. Restore the complete tool exchange first."
        release_lock "${history_file}.lock"
        return 1
    fi

    local status=0
    json_modify "$history_file" --argjson indexes "$selected_indexes" \
        "${jq_add_indexes} | ${restore_filter} | map(del(.index, .user_index, .assistant_index, .tool_index, .reasoning_index))" || status=$?
    release_lock "${history_file}.lock"
    return "$status"
}

history_prune() {
    local role=""
    local -a ranges=()

    # Default mode from config
    local mode=$(get_config "prune_mode")

    # Parse flags before ranges
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--assistant|-t|--tool|-u|--user|-r|--reasoning)
                if [[ -n "$role" ]]; then
                    die "Only one of --assistant, --tool, --user, or --reasoning can be specified."
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
        local jq_slice=$(range_defaults "$range" "$role")
        # Select entries in range and role
	local entries=$(jq --arg role "$role" '
	   map(select(.role == $role)) | .['"$jq_slice"']
	   ' "$tmpfile")
        local count=$(jq 'length' <<<"$entries" | read_file)
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
		  + (if has("data") then {data: .data} else {} end)
		)
	      else
	        .
	      end
	    )
	    '

	local i=0
        for (( i=0; i < count; i++ )); do
            local ts=$(jq -r ".[$i].timestamp" <<<"$entries" | read_file)
            local id=$(jq -r ".[$i].id" <<<"$entries" | read_file)
            local prune_id="${ts}-${id}"

            # Backup original if not already backed up
            # Get actual role_index of the entry
            local role_index=$(jq -r ".[$i].${role}_index" <<<"$entries" | read_file)
	    local global_index=$(jq -r ".[$i].index" <<<"$entries" | read_file)

	    local orig_content=$(jq -r "map(select(.index == $global_index)) | .[0].content" "$tmpfile" | read_file)
	    if [[ "$orig_content" == "null" ]] ; then
		orig_content=""
	    fi
            local orig_tool_calls=$(jq -r "map(select(.index == $global_index)) | .[0].tool_calls" "$tmpfile" | read_file)
	    if [[ "$orig_tool_calls" == "null" ]] ; then
		orig_tool_calls=""
	    fi
	    local new_content="$orig_content"
	    local new_tool_calls="$orig_tool_calls"

            if [[ "$mode" == "cut" ]]; then
                # Cut mode replaces content and/or tool_calls accordingly
		local trimmed_content=$(printf '%s' "$orig_content" | \
		    sed '/^\s*$/d;/^<<Original text reference: .*>>$/d;/^<<Pruned tool_calls>>$/d;')
                if [[ -n "$trimmed_content" ]]; then
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
		    # Delete the tool_calls first before we update the message, but make sure to mark the
		    # tool responses so the API still accept requests.
		    json_modify "$tmpfile" '
		      . as $messages |
		      ($messages['"$global_index"'].tool_calls // [] | map(.id)) as $pruned_ids |
		      map(
		        if .index == '"$global_index"' then
			   del(.tool_calls)
			elif .role == "tool" and
			     (.tool_call_id as $id | ($pruned_ids | index($id)) != null) then
			  . + {hidden: true, call_pruned: true}
			else
			  .
			end
		      )
		    '
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
                    local new_content=$(read_file "$edit_tmp")
                fi
                if [[ -n "$orig_tool_calls" ]]; then
                    printf '%s' "$orig_tool_calls" > "$edit_tmp"
		    # TODO, allow either MAIA_EDITOR or EDITOR
                    "$editor" "$edit_tmp"
                    local new_tool_calls=$(read_file "$edit_tmp")
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
		   "map(if .index == $global_index then .content = \$content else . end)"
	    fi
	    if [[ "$orig_tool_calls" != "$new_tool_calls" ]] ; then
		json_modify "$tmpfile" --arg tool_calls "$new_tool_calls" \
		   "map(if .index == $global_index then .tool_calls = \$tool_calls else . end)"
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

    # Load merged config
    local scope="session"
    load_config "$scope" CONFIG

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
		    prompt|turn*|last|last-*|all) range="$arg" ;;
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
	    local total=$(jq 'length' "$history_file" | read_file)
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
	    local total=$(jq 'length' "$history_file" | read_file)
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

	replace)
	    shift
	    [[ $# -eq 1 && "$1" =~ ^[0-9]+$ ]] || die "Usage: maia history replace <index>"
	    local replace_index="$1"
	    local replacement
	    replacement="$(cat)"
	    exclusive_json_modify "$history_file" --arg replacement "$replacement" --argjson index "$replace_index" '
	      .[$index] as $entry
	      | if ($entry | has("backup") | not) then
	          .[$index].backup = ({ }
	            + (if $entry | has("content") then {content: $entry.content} else {} end)
	            + (if $entry | has("tool_calls") then {tool_calls: $entry.tool_calls} else {} end)
	            + (if $entry | has("data") then {data: $entry.data} else {} end))
	        else . end
	      | .[$index].content = $replacement
	    '
	    info "History entry $replace_index replaced."
	    ;;

	restore)
	    shift
            if ! history_restore_range "$history_file" "${1:-}"; then
                return 1
            fi
	    info "Entries restored in history '$history_name'."
	    ;;

	hide)
	    shift
            if ! history_update_tool_relationships "$history_file" hide "${1:-}"; then
                return 1
            fi
            info "Entries hidden in history '$history_name'."
	    ;;

	unhide)
	    shift
            if ! history_update_tool_relationships "$history_file" unhide "${1:-}"; then
                return 1
            fi
            info "Entries unhidden in history '$history_name'."
	    ;;

	delete)
	    shift
	    if ! history_update_tool_relationships "$history_file" delete "${1:-}"; then
                return 1
            fi
	    info "Entries deleted from history '$history_name'."
	    ;;

	summarize|compact)
	    shift
	    . "$MAIA_CORE_LIB_DIR/send.sh"
	    local request=$(prompt_for_scope "session" "summarize")
	    local summary
	    summary=$(handle_send_command --no-files --no-tools --no-skills "$request")
	    local status=$?
	    if [[ -n "$summary" && $status -eq 0 ]] ; then
		exclusive_json_modify "$history_file" '
		    if length > 2 then
		      .[0:-2] |= map(.hidden = true | .summarized = true)
		    else
		      .
		    end
		'
	    else
		warn "Unable to make a summary. History not compacted."
	    fi
	    ;;

	prune)
	    shift
	    history_prune "$@"
	    ;;

	verify)
	    jq -f "$MAIA_CORE_LIB_DIR/history-verify.jq" "$history_file"
	    ;;

	repair)
	    exclusive_json_modify "$history_file" -f "$MAIA_CORE_LIB_DIR/history-repair.jq"
	    ;;

	search)
	    shift
	    # if no argument or an explicit empty-string is given, treat it like no-arg
	    local user_only=0 assistant_only=0 raw_output=0
	    # parse all args
	    local keyword=""
	    for arg in "$@"; do
		case "$arg" in
		    -u|--user)       user_only=1         ;;
		    -a|--assistant)  assistant_only=1    ;;
		    --raw|--json)    raw_output=1 ;;
		    *)
			[[ -z "$keyword" ]] && keyword="$arg"
			;;
		esac
	    done
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

    local role=""
    if (( user_only && ! assistant_only )); then
	role="user"
    elif (( assistant_only && ! user_only )); then
	role="assistant"
    fi
    local slice=$(range_defaults "$range" "$role")
    local role_filter
    if [[ -n "$role" ]] ; then
        role_filter="map(select(.role == \"${role}\"))"
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
	(.hidden // false),
        (.user_index // 0),
        (.assistant_index // 0),
        (.tool_index // 0),
        (.reasoning_index // 0),
        .timestamp,
        (.id // 0),
	(.tool_call_id // "-"),
        (.content | @base64),
        ((.tool_calls // "") | @base64)
    ] | @tsv' | while IFS=$'\t' read -r idx role hidden user_idx assistant_idx tool_idx reasoning_idx ts id toolid content_b64 tools_call_b64; do
	# Git Bash workaround
	tools_call_b64="$(strip_cr "$tools_call_b64")"
	local content=""
	if [[ -n "$content_b64" ]] ; then
            content=$(echo "$content_b64" | base64 --decode)
	fi
        # Replace null content with empty string
        if [[ "$content" == "null" ]] || [[ -z "$content" ]]; then
            content=""
        fi
        if [[ "$toolid" == "-" ]] || [[ -z "$toolid" ]]; then
            toolid=""
        fi

	local tools_call_json=""
	if [[ -n "$tools_call_b64" ]] ; then
	    tools_call_json=$(echo "$tools_call_b64" | base64 --decode)
	fi
        if [[ "$tools_call_json" == "null" ]] || [[ -z "$tools_call_json" ]]; then
            tools_call_json=""
        fi

        if [[ "$role" == "user" ]]; then
            role_idx="$user_idx"
        elif [[ "$role" == "assistant" ]]; then
            role_idx="$assistant_idx"
        elif [[ "$role" == "tool" ]]; then
            role_idx="$tool_idx"
        elif [[ "$role" == "reasoning" ]]; then
            role_idx="$reasoning_idx"
        else
            role_idx=""
        fi

	pr='[%d] %s#%s %s-%s\n'
	if [[ -n "$toolid" ]] ; then
	    pr='[%d] %s#%s %s-%s %s\n'
	fi
	if [[ "$hidden" == true ]] ; then
            printf "(hidden: $pr" "$idx" "$role" "$role_idx" "$ts" "$id)"
	else
	    printf "$pr" "$idx" "$role" "$role_idx" "$ts" "$id" $toolid
	    if [[ -z "$toolid" ]] ; then
		echo '----------------------------------------'
	    else
		echo '-------------------------------------------------'
	    fi
            printf '%s\n\n' "$content"

            # If assistant message has function_call, print it visibly
	    if [[ "$role" == "assistant" && -n "$tools_call_json" && "$tools_call_json" != "null" ]]; then
		mapfile_from_command tool_calls jq -c '.[]' <<<"$tools_call_json"
		for tool_call in "${tool_calls[@]}"; do
		    id=$(jq -r '.id // empty' <<<"$tool_call" | read_file)
		    func_name=$(jq -r '.function.name // empty' <<<"$tool_call" | read_file)
		    func_args=$(jq -r '.function.arguments // empty' <<<"$tool_call" | read_file)

		    if [[ -n "$func_name" ]]; then
			echo "[tool call] $id $func_name($func_args)"
			echo
		    fi
		done
	    fi
	fi

    done
}
