#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
. "$MAIA_CORE_LIB_DIR/send.sh"

chat_usage() {
    cat <<'EOF'
USAGE

  maia chat [<text-or-file>…] [options]

Start or invoke MAIA chat mode.

With arguments:
  Acts exactly like “maia send <args>” and then exits.

Without arguments:
  Enters an interactive chat prompt “Chat> ”  
  – Unrecognized lines are sent as messages.  
  – Recognized MAIA subcommands (e.g. config, user, etc.) are invoked locally.
  Type “exit” or “quit” (or press Ctrl-D) to leave.

OPTIONS

  -h, --help
    Show this help message and exit.
EOF
    exit 0
}

expand_snippets_in_line() {
    local line="$1"
    local expanded="$line"

    # Find all occurrences of '@' followed by valid snippet name [a-zA-Z0-9_-]+
    # Use grep -oP or bash regex matching (if available)
    # Here we use bash regex and a loop

    local re='@([a-zA-Z0-9_-]+)'
    while [[ "$expanded" =~ $re ]]; do
        local snippet_name="${BASH_REMATCH[1]}"
        local snippet_content
        if snippet_content=$(expand_snippet_name "$snippet_name" 2>/dev/null); then
            # Escape snippet_content for safe substitution (handle special chars)
            # Replace only the first occurrence of @snippet_name
            expanded="${expanded//@$snippet_name/$snippet_content}"
        else
            # Snippet not found, leave as-is or optionally warn
            # For now, leave as-is
            # Or: echo "Warning: snippet '$snippet_name' not found" >&2
            # break or continue
	    warn "Snippet @$snippet_name not found and not expanded."
            break
        fi
    done

    echo "$expanded"
}

handle_chat_command() {
    # If the user asked for help:
    [[ "$1" =~ ^-h|--help$ ]] && chat_usage
    # Not needed but we keep it for future compatibility if we implement
    # a sub-command.
    [[ "$2" =~ ^-h|--help$ ]] && chat_usage
    if [ $# -gt 0 ]; then
	handle_send_command "$@"
	return
    fi

    echo "MAIA chat mode. Type 'exit' or 'quit' to leave."
    while true; do
	if ! read -rp "Chat> " line; then
	    info "Exiting chat."
	    break
	fi
	case "$line" in
	    exit|quit)
		info "Exiting chat."
		break
		;;
	    '') continue ;;
	    *)
		# Split input to detect if it starts with a known command
		read -ra tokens <<< "$line"
		if is_known_command "${tokens[0]}"; then
		    "$0" $line
		else
		    local expanded_line=$(expand_snippets_in_line "$line")
		    handle_send_command "$expanded_line"
		fi
		;;
	esac
    done
}
