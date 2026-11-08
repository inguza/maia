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
  maia approve [--scope <scope>]

Manage file-operation approvals. Rules use shell globs relative to the
workspace root.

COMMANDS

  list

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

    local scope="" scopearg="" subcmd
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                approve_usage
                ;;
            --scope)
                shift
                [[ -n "${1:-}" ]] || die "Scope required after --scope"
                scope="$1"
                shift
                scopearg="yes"
                ;;
            *)
                break
                ;;
        esac
    done

    determine_implicit_scope approval
    if [[ "$scopearg" == "yes" && -z "$scope" ]]; then
        printf '%s\n' "$implicit_scope"
        return
    fi
    subcmd="${1:-show}"
    [[ $# -gt 0 ]] && shift
    [[ "$subcmd" == "allow" || "$subcmd" == "enable" ]] && subcmd="append"

    [[ -n "$scope" ]] || scope="session"
    validate_scope "$scope"
    [[ "$scope" != "default" ]] || die "The default scope cannot store approval rules."
    load_config "$scope" CONFIG

    local filepath="${SCOPE_DIR[$scope]}/approval.txt"
    case "$subcmd" in
        show|view|list)
            prompt_for_scope "$scope" approval
            ;;
        append)
            [[ $# -gt 0 ]] || die "Usage: maia approve append <path-pattern>:<action>..."
            mkdir -p "${SCOPE_DIR[$scope]}"
            copy_over "$scope" approval "$filepath"
            handle_text_file_command "$filepath" append "$@"
            deduplicate_files "$filepath"
            ;;
        replace)
            [[ $# -gt 0 ]] || die "Usage: maia approve replace <path-pattern>:<action>..."
            mkdir -p "${SCOPE_DIR[$scope]}"
            handle_text_file_command "$filepath" replace "$@"
            deduplicate_files "$filepath"
            ;;
        disable)
            [[ $# -gt 0 ]] || die "Usage: maia approve disable <exact-rule>..."
            mkdir -p "${SCOPE_DIR[$scope]}"
            copy_over "$scope" approval "$filepath"
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
        clear)
            mkdir -p "${SCOPE_DIR[$scope]}"
            : > "$filepath"
            ;;
        delete)
            rm -f "$filepath"
            ;;
        *)
            die "Unknown approve subcommand: $subcmd"
            ;;
    esac
}
