# Manage the system prompt (system.txt) in various scopes
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

system_usage() {
    cat <<'EOF'
USAGE

  maia system [--scope <scope>] <command> [<text-or-file>…]
  maia system [<text-or-file>…]

Manage your system-prompt in various scopes.

COMMANDS

  show
    Display the prompt (searching from the given or implicit scope).

  append <...>
    Add text or file contents to the end of the prompt file.

  edit
    Edit the text.

  read
    Append text from stdin.

  replace <...>
    Clear and then append.

  clear
    Empty the prompt file.

  delete
    Remove the prompt file.

OPTIONS

  -h, --help
    Show this help and exit.

  --scope <s>
    Explicitly select one of session, workspace, home, user, system.

  --type <t>
    Which prompt to manage:
      - system (default)
      - tools
      - files
      - tools
      - toolscontext

SCOPES

  session
    <maia_home>/histories/<history>.system.txt

  workspace
    <maia_home>/projects/<project>.system.txt

  home
    first matching .maia in cwd/ancestors

  user
    ~/.maia/system.txt (or $MAIA_HOME/.maia)

  system
    read-only /etc/maia/system.txt

NOTES

  When maia system [<text-or-file>] alternative is detected it is treated as
  'maia system append [<text-or-file>]' except that the <text-or-file> must
  either start with a capital letter or be a quoted string with at least one
  space.

  If no --scope is given, the CLI searches for an existing <type>.txt in the
  order session, workspace, home, user, system; and uses that same scope for
  reads and writes. If it does not find a suitable file, then home is used
  as scope.

  <text-or-file> can be any of the following:
    - a word
    - a "quoted text"
    - +command (compose, read, edit, run)
    - =filename (content of a file)
    - ++word (litteral +word)
    - ==word (litteral =word)
    - @snippet
  If multiple are provided they are appended as new lines (except for edit
  which opens the editor inline).

EOF
    exit 0
}

handle_system_command() {
    # help
    [[ "$1" =~ ^-h|--help$ ]] && system_usage
    [[ "$2" =~ ^-h|--help$ ]] && system_usage

    # defaults
    local prompt_type="system"
    local scope=""
    local subcmd
    local filename
    local filepath
    local consumed=""

    # 1) consume global flags: -h/--help, --type, --scope
    local scopearg=""
    while [[ $# -gt 0 ]]; do
	case "$1" in
	    -h|--help)
		system_usage
		return 0
		;;
	    --type)
		consumed="$consumed $1 $2"
		shift
		prompt_type="$1"; shift || true
		case "$prompt_type" in
		    system|files|tools|skills|skillscontext)
			:
			;;
		    *)
			die "Unknown type '$prompt_type'. Valid: system, files, tools, tool_instr."
			;;
		esac
		;;
	    --scope)
		consumed="$consumed $1 $2"
		shift
		scope="$1"; shift || true
		scopearg=yes
		if [[ -n "$scope" ]] ; then
		    if [[ -z "${SCOPE_DIRS[$scope]+x}" ]]; then
			die "Unknown scope '$scope'. Valid scopes: ${!SCOPE_DIRS[*]}"
		    fi
		fi
		;;
	    *)
		break
		;;
	esac
    done

    # default scope if none given
    determine_implicit_scope "$prompt_type"
    if [[ "$scopearg" = "yes" && -z "$scope" ]] ; then
	echo "$implicit_scope"
	return
    fi
    if [[ -z "$scope" && "$implicit_scope" != "default" && "$implicit_scope" != "system" ]]; then
	scope="$implicit_scope"
    fi
    if [[ -z "$scope" ]]; then
	scope="home"
    fi

    # now parse subcommand
    subcmd="${1:-}"

    # compute filename & path
    filename="${prompt_type}.txt"
    filepath="${SCOPE_DIRS[$scope]}/$filename"
    case "$subcmd" in
	show|"")
	    # just fetch via our common helper
	    prompt_for_scope "$scope" "$prompt_type"
	    ;;
	append)
	    # seed on first append
	    mkdir -p "${SCOPE_DIRS[$scope]}"
	    if [[ ! -f "$filepath" ]]; then
		local msg=$(prompt_for_scope "$implicit_scope" "$prompt_type")
		if [[ -z "$msg" ]] ; then
		    touch "$filepath"
		else
		    echo "$msg" > "$filepath"
		fi
	    fi
	    handle_text_file_command "$filepath" "$@"
	    ;;

	edit|read|compose|replace|clear|delete)
	    mkdir -p "${SCOPE_DIRS[$scope]}"
	    handle_text_file_command "$filepath" "$@"
	    ;;

	*)
	    if ! is_first_letter_upper "$subcmd" && [[ "$subcmd" != *" "* ]]; then
		error "Unrecognized command '$subcmd'. Use a capitalized command or quote a multi-word message."
		system_usage
	    fi
	    handle_system_command $consumed "append" "$@"
	    ;;
    esac
}
