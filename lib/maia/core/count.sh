#`maia count` / `maia c` using a Bash heuristic (chars/4 ≈ tokens)
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

. "$MAIA_CORE_LIB_DIR/user.sh"
. "$MAIA_CORE_LIB_DIR/send.sh"  # for build_messages_json

count_usage() {
    cat <<'EOF'
USAGE

  maia count [--model <model>] [<text-or-file>…]

Prints an approximate token count (chars/4 ≈ tokens) per message and total.
Also prints an approximate cost in USD assuming a cost per token based on the model,
separately for user and assistant messages.

COMMANDS

  (No subcommands)

OPTIONS

  --model <model>
    Specify the model to use for cost calculation (overrides config).
    Supported models: gpt-4, gpt-4-32k, gpt-3.5-turbo, gpt-4.1-mini.

  --file-handling <mode>
    Override file handling mode for this send command.
    Allowed values: DEFAULT, BEFORE, APPEND (case-insensitive).

  -h, --help
    Show this help message and exit.

EXAMPLES

    maia count --model gpt-4 file.txt
      Estimate token count and cost for the contents of file.txt using GPT-4.

NOTES

  The token count is an approximation calculated as characters divided by 4.
  Costs are calculated separately for user and assistant tokens.

  It is also important to understand that the assistant cost was for that
  specific assistant reply. The user cost is for each time that is sent
  and that do not count the fact that assistant reply is also counted.

  <text-or-file> can be any of the following:
  - A Word
  - a "quoted text"
  - the command compose
  - the command read
  - the command edit
  If multiple are provided they are appended as new lines (except edit).

EOF
    exit 0
}

handle_count_command() {
    # Help
    [[ "$1" =~ ^-h|--help$ ]] && count_usage
    [[ "$2" =~ ^-h|--help$ ]] && count_usage

    # Parse arguments for --model option
    local model=$(jq -r '.model' <<<"$_cfg")
    local file_handling_mode_raw
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)
                shift
                if [[ -z "$1" ]]; then
                    echo "Error: --model requires an argument." >&2
                    return 1
                fi
                model="$1"
                shift
                ;;
            --file-handling-mode)
                shift
                if [[ -z "$1" ]]; then
                    echo "Error: --file-handling-mode requires an argument." >&2
                    return 1
                fi
                file_handling_mode_raw="$1"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    # Restore positional parameters after parsing options
    set -- "${args[@]}"

    # Normalize model key for cost keys: replace dots and dashes with underscores
    local model_key="${model//./_}"
    model_key="${model_key//-/_}"

    # Extract cost per token for user and assistant from config or fallback to defaults
    local cost_input_key="cost_input_${model_key}"
    local cost_output_key="cost_output_${model_key}"

    local cost_input=$(jq -r --arg key "$cost_input_key" '.[ $key ] // empty' <<<"$_cfg")
    local cost_output=$(jq -r --arg key "$cost_output_key" '.[ $key ] // empty' <<<"$_cfg")

    # Determine history and outbox
    local history_dir=$(resolve_session_path)
    local outbox_file="$history_dir/outbox.txt"

    ensure_session_exists
    # Append any remaining arguments to outbox
    if [ $# -gt 0 ]; then
        handle_user_command append "$@"
    fi

    # Inform if outbox empty
    if [ ! -s "$outbox_file" ]; then
        notice "Outbox is empty. Counting historical cost."
    fi

    # Build the shared messages payload
    local messages_json=$(build_messages_json "$outbox_file" "$model" "$file_handling_mode_raw")

    # Iterate messages via jq and estimate tokens by role
    local count idx role content len tokens
    local total_tokens=0
    local total_user_tokens=0
    local total_assistant_tokens=0
    local last_assistant_tokens=0

    count=$(jq 'length' <<<"$messages_json")
    echo
    echo "Approximate token counts per message (chars/4 ≈ tokens):"
    index=0
    uindex=0
    aindex=0
    for idx in $(seq 0 $((count - 1))); do
        role=$(jq -r ".[$idx].role" <<<"$messages_json")
        content=$(jq -r ".[$idx].content" <<<"$messages_json")
        len=${#content}
        tokens=$(((len + 3) / 4))
	sindex=
	xindex=
        if [[ "$role" == "user" ]]; then
	    sindex=$index
	    xindex="[$uindex]"
        elif [[ "$role" == "assistant" ]]; then
	    sindex=$index
	    xindex="[$aindex]"
	fi	    
        printf "%-3d  %-12s -> %4d tokens (chars: %d)\n" $index "${role^^}$xindex" "$tokens" "$len"
        total_tokens=$((total_tokens + tokens))
        if [[ "$role" == "user" ]]; then
            total_user_tokens=$((total_user_tokens + tokens))
	    ((index++))
	    ((uindex++))
        elif [[ "$role" == "assistant" ]]; then
	    last_assistant_tokens=$tokens
            total_assistant_tokens=$((total_assistant_tokens + tokens))
	    ((index++))
	    ((aindex++))
        fi
    done
    local total_input_tokens=$(echo "$total_user_tokens + $total_assistant_tokens - $last_assistant_tokens" | bc -l)
    local total_output_tokens=$last_assistant_tokens
    echo "──────────────────────────────"
    printf "APPROXIMATE TOKENS for model '%s':\n" "$model"
    printf "Total:        %4d\n" "$total_tokens"
    printf "  Input:      %4d\n" "$total_input_tokens"
    printf "  Output:     %4d\n" "$total_output_tokens"
    echo "──────────────────────────────"
    printf "  User:       %4d\n" "$total_user_tokens"
    printf "  Assistant:  %4d\n" "$total_assistant_tokens"

    if [[ ! $cost_input || ! $cost_output ]] ; then
	warn "Cost configuration missing for model '$model'"
	return
    fi
    # Calculate and display approximate cost separately for user and assistant
    local cost_input_total=$(echo "$total_input_tokens * $cost_input / 1000000" | bc -l)
    local cost_output_total=$(echo "$total_output_tokens * $cost_output / 1000000" | bc -l)
    local cost_total=$(echo "$cost_input_total + $cost_output_total" | bc -l)
    
    LC_NUMERIC=C printf "APPROXIMATE COST (USD) for model '%s':\n" "$model"
    LC_NUMERIC=C printf "  Total:      \$%.6f\n" "$cost_total"
    LC_NUMERIC=C printf "  Input:      \$%.6f\n" "$cost_input_total"
    LC_NUMERIC=C printf "  Output:     \$%.6f\n" "$cost_output_total"
    echo "The input cost is a prediction of what will be sent."
    echo "The output cost is based on last request."
}
