#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

interactive_usage() {
    cat <<'EOF'
USAGE

  maia interactive [options]

Start the MAIA interactive REPL.

Each line you type is run as “maia <that line>”.
Type “exit” or “quit” (or press Ctrl-D) to leave.

OPTIONS

  -h, --help
    Show this help message and exit.
EOF
    exit 0
}

handle_interactive_command() {
    # If the user asked for help:
    [[ "$1" =~ ^-h|--help$ ]] && interactive_usage
    info "MAIA interactive mode. Type 'exit' or 'quit' to leave."
    while true; do
	# break on Ctrl-D
	if ! read -rp "> " line; then
	    notice "Goodbye."
	    break
	fi
	case "$line" in
	    exit|quit)
		info "Goodbye."
		break
		;;
	    '') continue ;;
	    *)
		"$0" $line
		;;
	esac
    done
}
