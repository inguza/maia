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

  show [options] [<range>]
    Display entries in the given range.

  pop [options] [<n>]
    Remove & print last n entries (default 1).

  top [options] [<n>]
    Remove & print first n entries (default 1).

  delete [<range>]
    Delete entries in n–m inclusive.

  prune [<range> [options]]
    Options to override the default 'prune_mode' configuration.
    --reduce replace large blocks with a placeholder
    --edit adjust in an editor
    --cut replace the entire message with a placeholder

  search [options] <keyword>
    Find entries containing keyword.

  clear
    Wipe the active history.

OPTIONS

  -h, --help
    Show this help message and exit.

  -a, --assistant
    Only show assistant messages. Applicable to show and search.

  -u, --user
    Only show user messages. Applicable to show and search.

  If both --user and --assistant are provided, it shows both.

  --raw, --json
    Print in json format. Applicable to show, search, pop and top.

EXAMPLES

    maia history show 0-10
      Show the first 11 entries in history.

    maia history pop 2
      Remove and print the last two entries.

    maia history
      Show the last assistant response.

    maia history -
      Show full history.

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

EOF
    exit 0
}

readonly PRUNE_CUT_PLACEHOLDER='<<Assistant response removed from history to conserve space>>'

# Global readonly variable for jq filter to add indexes
readonly jq_add_indexes='
  [ foreach .[] as $item (
      { index: -1, user: 0, assistant: 0 };
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

# Prune assistant messages by removing fenced code blocks and large blockquote blocks,
# replacing each removed block with <<BLOCK #n: pruned>> where n is the assistant message zero-based index.
# Usage:
#   prune [<range or n>]
# By default, prune last assistant message.
history_prune() {
    local range="last"
    local mode=$(jq -r '.prune_mode' <<<"$_cfg")
    # Parse args: if last arg is one of --reduce, --edit, --cut, set mode accordingly
    # Otherwise first arg is range, optional second arg is mode string
    # Allow both styles for backward compatibility
    if [[ "$#" -ge 1 ]]; then
        case "$1" in
            --reduce|--edit|--cut)
                mode="${1#--}"
                ;;
            *)
                range="$1"
                if [[ "$#" -ge 2 ]]; then
                    case "$2" in
                        --reduce|--edit|--cut)
                            mode="${2#--}"
                            ;;
                    esac
                fi
                ;;
        esac
    fi

    local history_file="$(resolve_history_meta)"
    local jq_slice
    jq_slice=$(range_defaults "$range")

    local entries_json=$(jq '
        map(select(.role == "assistant")) | .['"$jq_slice"']
    ' "$history_file")

    local count=$(jq 'length' <<<"$entries_json")

    if [[ "$mode" == "cut" ]]; then
        local tmpfile=$(mktemp)
        cp "$history_file" "$tmpfile"
        for (( i=0; i<count; i++ )); do
            local ts=$(jq -r ".[$i].timestamp" <<<"$entries_json")
            local id=$(jq -r ".[$i].id" <<<"$entries_json")
            jq --arg ts "$ts" --arg id "$id" --arg content "$PRUNE_CUT_PLACEHOLDER" \
               'map(if .timestamp == $ts and .id == $id and .role == "assistant" then .content = $content else . end)' \
               "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
        done
        mv "$tmpfile" "$history_file"
        info "Assistant messages content replaced with placeholder in range '$range'."
        return
    elif [[ "$mode" == "edit" ]]; then
        local tmpfile=$(mktemp)
        cp "$history_file" "$tmpfile"
        for (( i=0; i<count; i++ )); do
            local ts=$(jq -r ".[$i].timestamp" <<<"$entries_json")
            local id=$(jq -r ".[$i].id" <<<"$entries_json")
            local orig_content=$(jq -r ".[$i].content" <<<"$entries_json")
            local edit_tmp=$(mktemp)
            printf '%s' "$orig_content" > "$edit_tmp"
            "${EDITOR:-vi}" "$edit_tmp"
            local new_content=$(cat "$edit_tmp")
            rm -f "$edit_tmp"
            jq --arg ts "$ts" --arg id "$id" --arg content "$new_content" \
               'map(if .timestamp == $ts and .id == $id and .role == "assistant" then .content = $content else . end)' \
               "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
        done
        mv "$tmpfile" "$history_file"
        info "Assistant messages edited in range '$range'."
        return
    elif [[ "$mode" == "reduce" ]]; then
        local tmpfile=$(mktemp)
        cp "$history_file" "$tmpfile"
        for (( i=0; i<count; i++ )); do
            local ts=$(jq -r ".[$i].timestamp" <<<"$entries_json")
            local id=$(jq -r ".[$i].id" <<<"$entries_json")
            local orig_content=$(jq -r ".[$i].content" <<<"$entries_json")
            local pruned_content=$(prune_content "$orig_content" "$i")
            jq --arg ts "$ts" --arg id "$id" --arg content "$pruned_content" \
               'map(if .timestamp == $ts and .id == $id and .role == "assistant" then .content = $content else . end)' \
               "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
        done
        mv "$tmpfile" "$history_file"
        info "Assistant messages pruned (reduced) in range '$range'."
        return
    else
        die "Unknown prune mode: '$mode'. Valid modes are reduce, edit, cut."
    fi
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
	    jq ".[0: -$n]" "$history_file" > "$tmp" && mv "$tmp" "$history_file"
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
	    jq ".[ $n :]" "$history_file" > "$tmp" && mv "$tmp" "$history_file"
	    info "Popped the first $n entr$([ "$n" -eq 1 ] && echo "y" || echo "ies") from history '$history_name'."
	    ;;

        delete)
	    shift
	    local slice=$(range_defaults "${1:-}")
	    jq "del(.[${slice}])" "$history_file" > "$history_file.tmp" && mv "$history_file.tmp" "$history_file"
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
	    echo "[]" > "$history_file"  # Clear the entire history file
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
