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

  maia approve [--type <type>] [--scope <scope>] <command>
  maia approve --scope
      Show the effective scope for the selected rule type.

Manage file approvals (default), execution approvals, or executable rule
definitions. Each type is stored independently in the selected scope.

Possible actions to approve:
 - append - Append data to a file
 - create - Create a file
 - change - Change content in a file (also allows append)
 - delete - Delete a file
 - write  - Allows create and change. Also allow a file to be moved.


COMMANDS

  view

  append|enable|allow <path-pattern>:<action> [...]
      Add an approval entry.
  
  replace <path-pattern>:<action> [...]
      Replace approval definition (same as clear and append)

  disable <string> [<string> [...]]
      Remove exact approval entries from the specified scope.

  change <existing-line> <new-line>
      Replace one exact approval entry. Quote lines containing spaces.

  clear
      Clear all approval definitions in the specified scope.

  delete
      Delete approval definitions from the specified scope.

Example:
  maia approve allow 'logs/*:append'

OPTIONS

  --scope <scope>  Use session, profile, workspace, home, user, or system.
  --type <type>    Select file (default), exec, or exec-def rules.
  -h, --help       Show this help message and exit.
EOF
    exit 0
}

handle_approve_command() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${2:-}" == "-h" || "${2:-}" == "--help" ]]; then
        approve_usage
    fi

    local scope="" scopearg="" approval_type="file" approval_filename="file-approval.txt"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                approve_usage
                ;;
            --scope)
                scopearg=yes
                if (($# >= 2)) && [[ "$2" != -* ]]; then
                    scope="$2"
                    shift 2
                else
                    scope=""
                    shift
                fi
                ;;
            --type)
                if (($# < 2)); then
                    die "Missing value for --type."
                fi
                approval_type="$2"
                shift 2
                case "$approval_type" in
                    file) approval_filename="file-approval.txt" ;;
                    exec) approval_filename="exec-approval.txt" ;;
                    exec-def) approval_filename="exec-def.txt" ;;
                    *) die "Unknown approval type: $approval_type (expected file, exec, or exec-def)." ;;
                esac
                ;;
            *)
                break
                ;;
        esac
    done
    local prompt_type="approval"

    local subcmd="${1:-view}"
    shift || true

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
    load_settings "$scope"

    local filepath="${SCOPE_DIR[$scope]}/${approval_filename}"

    case "$subcmd" in
	append|enable|allow)
	    mkdir -p "${SCOPE_DIR[$scope]}"
            # Start an explicit definition by inheriting this rule type's
            # effective file from the selected scope, then append the new entry.
            if [[ ! -f "$filepath" ]]; then
                local inherited_file
                inherited_file="$(file_for_scope "$scope" "$approval_filename")"
                if [[ -n "$inherited_file" && "$inherited_file" != "$filepath" && -f "$inherited_file" ]]; then
                    cp -- "$inherited_file" "$filepath"
                elif [[ "$approval_type" == file ]]; then
                    prompt_for_scope default "$prompt_type" > "$filepath"
                else
                    : > "$filepath"
                fi
            fi
	    subcmd="append"
	    ;;
        disable|change|edit)
            mkdir -p "${SCOPE_DIR[$scope]}"
            if [[ ! -f "$filepath" ]]; then
                local inherited_file
                inherited_file="$(file_for_scope "$scope" "$approval_filename")"
                if [[ -n "$inherited_file" && "$inherited_file" != "$filepath" && -f "$inherited_file" ]]; then
                    cp -- "$inherited_file" "$filepath"
                elif [[ "$approval_type" == file ]]; then
                    prompt_for_scope default "$prompt_type" > "$filepath"
                else
                    : > "$filepath"
                fi
            fi
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
            local effective_file
            effective_file="$(file_for_scope "$scope" "$approval_filename")"
            if [[ -n "$effective_file" && -f "$effective_file" ]]; then
                read_file_by_line "$effective_file"
            elif [[ "$approval_type" == file ]]; then
                prompt_for_scope default "$prompt_type"
            fi
            ;;
        append|edit|change|replace|delete|clear|clearnonotice)
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
