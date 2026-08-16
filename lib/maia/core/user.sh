#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

user_usage() {
    cat <<'EOF'
USAGE

  maia user <command> [ARGS...]
  maia user [<text-or-file>...]

Manage the user outbox: show, append, replace, clear, delete.

COMMANDS

  show
    Print pending outbox.

  edit
    Edit the outbox.

  append <text>
    Append text or file to outbox.

  replace <text>
    Replace outbox content.

  clear
    Remove outbox entirely.

  delete
    Delete the outbox file.

OPTIONS

  -h, --help
    Show this help message and exit.

EXAMPLES

    maia user append "New message"
      Append "New message" to the outbox.

    maia user show
      View the current outbox content.

NOTES

  When 'maia user [<text-or-file>]' is called without a command, it is 
  treated as 'maia user append [<text-or-file>]' only if the argument starts 
  with a capital letter or is a quoted string with at least one space.

  You can also run:

    maia user append read
      Read from stdin.

    maia user append compose
      Open an editor to compose the text.

    maia user "This is the error message I get:" compose
      First add the text and then open up an editor for the error message.

    maia user show
      Show what's in the outbox.

  <text-or-file> can be any of the following:
  - A Word
  - a "quoted text"
  - the command compose
  - the command read
  - the command edit
  If multiple are provided they are appended as new lines (except edit) which
  opens the editor inline.

EOF
    exit 0
}

handle_user_command() {
    [[ "$1" =~ ^-h|--help$ ]] && user_usage
    [[ "$2" =~ ^-h|--help$ ]] && user_usage
    # No arecognized command, but args were passed → default to `u append`, but not always

    local subcmd="${1:-}"  # Default to "show" if no subcommand is provided

    local path="$(resolve_session_path)"
    mkdir -p "$path"
    local outbox_file="$path/outbox.txt"
    case "$subcmd" in
	"")
	    handle_text_file_command "$outbox_file" show "$@"
	    ;;
	edit|show|append|read|compose|replace|clear|delete)
	    handle_text_file_command "$outbox_file" "$@"
	    ;;
	*)
	    if ! is_first_letter_upper "$subcmd" \
		    && [[ "$subcmd" != *" "* \
		    && ! -e "$subcmd" ]]; then
		die "Unrecognized command '$subcmd'. Use a capitalized command or quote a multi-word message."
	    fi
	    handle_text_file_command "$outbox_file" append "$@"
	    ;;
    esac
}
