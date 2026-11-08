# Approval rules and CLI management.
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

approve_usage() {
    cat <<'EOF'
USAGE

  maia approve [--scope <scope>] <command>
  maia approve --scope
      Show the effective scope for approval rules.

Manage file-operation approvals. Rules use shell globs relative to the
workspace root.

COMMANDS

  view

  append|enable|allow <path-pattern>:<action> [...]
      Add an approval entry.
  
  replace <path-pattern>:<action> [...]
      Replace approval definition (same as clear and append)

  disable <string> [<string> [...]]
      Remove exact approval entries from the specified scope.

  clear
      Clear all approval definitions in the specified scope.

  delete
      Delete approval definitions from the specified scope.

Example:
  maia approve allow 'logs/*:append'

OPTIONS

  --scope <scope>  Use session, profile, workspace, home, user, or system.
  -h, --help       Show this help message and exit.
EOF
    exit 0
}

handle_approve_command() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${2:-}" == "-h" || "${2:-}" == "--help" ]] && approve_usage

    local scope="" scopearg=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                approve_usage
                ;;
            --scope)
                shift
                scope="$1"
                shift || true
                scopearg=yes
                ;;
            *)
                break
                ;;
        esac
    done
    local prompt_type="approval"

    local subcmd="${1:-show}"
    shift

    determine_implicit_scope "$prompt_type"
    if [[ "$scopearg" == "yes" && -z "$scope" ]]; then
        printf '%s\n' "$implicit_scope"
        return
    fi

    # Special default scope handling
    if [[ -z "$scope" ]]; then
	case "$subcmd" in
	    list)
		scope="$implicit_scope"
		;;
	    *)
		:
		;;
	esac
    fi

    if [[ -z "$scope" ]]; then
	scope="session"
    fi

    validate_scope "$scope"
    [[ "$scope" != "default" ]] || die "The default scope cannot store approval rules."
    load_config "$scope" CONFIG

    local filepath="${SCOPE_DIR[$scope]}/${prompt_type}.txt"

    case "$subcmd" in
	append|enable|allow)
	    mkdir -p "${SCOPE_DIR[$scope]}"
	    # Start an explicit definition by inheriting the effective raw
	    # definition from the selected scope, then append the new entry.
	    copy_over "$scope" "$prompt_type" "$filepath"
	    subcmd="append"
	    ;;
        disable)
	    mkdir -p "${SCOPE_DIR[$scope]}"
	    copy_over "$scope" "$prompt_type" "$filepath"
	    ;;
        clear|clearnonotice)
            mkdir -p "${SCOPE_DIR[$scope]}"
            : > "$filepath"
            ;;
	*)
	    :
	    ;;
    esac

    case "$subcmd" in
        view|"")
            prompt_for_scope "$scope" "$prompt_type"
            ;;
        append|edit|replace|delete|clear|clearnonotice)
            mkdir -p "${SCOPE_DIR[$scope]}"
            handle_text_file_command "$filepath" "$subcmd" "$@"
            deduplicate_files "$filepath"
            ;;
        disable)
            local tmpfile entry line remove
            tmpfile="$(mktemp)"
            while IFS= read -r line || [[ -n "$line" ]]; do
                remove=false
                for entry in "$@"; do
                    if [[ "$line" == "$entry" ]]; then
                        remove=true
                        break
                    fi
                done
                [[ "$remove" == true ]] || printf '%s\n' "$line" >> "$tmpfile"
            done < "$filepath"
            mv "$tmpfile" "$filepath"
            ;;
        *)
            die "Unknown approve subcommand: $subcmd"
            ;;
    esac
}
