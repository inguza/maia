#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

snippet_usage() {
    cat <<'EOF'
USAGE

  maia snippet [--scope <scope>] <command> [<name>] [<text-or-file>...]
  maia snippet [--scope <scope>] <name> [<text-or-file>...]
     If <text-or-file> is present default to show, else to append.

Manage named reusable user message snippet.

COMMANDS

  list
    List all snippet names available in the effective scope(s).

  show <name>
    Display the content of the named snippet.

  append <name> <text-or-file>...
    Append text or file contents to the end of the snippet (append).
    If no scope is given and an earlier name exists in another scope
    the text is first copied from the other scope to the current and
    then the text is appended to that.

  add <name> <text-or-file>...
    Add text or file contents to the end of the snippet (append).

  replace <name> <text-or-file>...
    Replace the content of the named snippet.

  edit <name>
    Edit the snippet file.

  delete <name>
    Delete the named snippet.

FLAGS

  -h, --help
    Show this help and exit.

  --scope <scope>
    Explicitly select one of history, workspace, home, user, system.

NOTES

  - If --scope is omitted, commands search all scopes in priority order for
    show, delete, and list; add and replace write to the highest priority
    writable scope (default: home if exists, else user).

  - Snippets are stored as plain text files under <scope_dir>/snippets/<name>.txt.

  <text-or-file> can be any of the following:
    - a word
    - a "quoted text"
    - +command (compose, read, edit, run, shell)
    - =filename (content of a file)
    - ++word (litteral +word)
    - ==word (litteral =word)
    - @snippet
  If multiple are provided they are appended as new lines (except for edit
  which opens the editor inline).

EOF
    exit 0
}

# List all snippet merged from all scopes, highest priority first
# Usage: list_all_snippet [withscope]
# If "withscope" is passed, echoes lines as "<name>|<scope>"
list_all_snippet() {
    local withscope="$1"
    local -A seen=()
    #init_snippet_scope_dirs

    for s in "${SCOPE_ORDER[@]}"; do
	[[ "$s" == "default" ]] && continue
        local dir="${SCOPE_DIRS[$s]}/snippets"
        if [[ -d "$dir" ]]; then
            for f in "$dir"/*.txt; do
                [[ -f "$f" ]] || continue
                local name
                name="$(basename "$f" .txt)"
                if [[ -z "${seen[$name]}" ]]; then
                    seen[$name]=$s
                    if [[ "$withscope" == "withscope" ]]; then
                        echo "$name|$s"
                    else
                        echo "$name"
                    fi
                fi
            done
        fi
    done
}

# Determine default writable scope for adding/replacing snippet
# Prefer workspace if exists and writable, else user scope
default_writable_scope() {
    if [[ -d "${SCOPE_DIRS[home]}" && -w "${SCOPE_DIRS[home]}" ]]; then
        echo "home"
    elif [[ -d "${SCOPE_DIRS[user]}" && -w "${SCOPE_DIRS[user]}" ]]; then
        echo "user"
    else
        # fallback to user anyway
        echo "user"
    fi
}

handle_snippet_command() {
    local scope=""
    local subcmd=""
    local name=""
    local args=()

    # Parse global flags before subcommand
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                snippet_usage
                ;;
            --scope)
                shift
                if [[ $# -eq 0 ]]; then
                    die "--scope requires an argument"
                fi
                scope="$1"
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    # The next argument should be subcommand or list (if none)
    subcmd="$1"

    case "$subcmd" in
        list|ls)
	    shift
            # list all snippet in all scopes (merged)
            if [[ "$1" == "--with-scope" ]]; then
                list_all_snippet withscope
            else
                list_all_snippet
            fi
            ;;
        show)
	    shift
            name="$1"
            [[ -n "$name" ]] || die "Missing snippet name for show"
            if [[ -n "$scope" ]]; then
                local file=$(snippet_file_path "$scope" "$name")
                if [[ -f "$file" ]]; then
                    cat "$file"
                else
                    die "Snippet '$name' not found in scope '$scope'"
                fi
            else
                local found=$(find_snippet_scope_and_path "$name") || die "Snippet '$name' not found in any scope"
                local found_scope="${found%%|*}"
                local found_file="${found#*|}"
                cat "$found_file"
            fi
            ;;
	append)
	    shift
            name="$1"
            shift
            [[ -n "$name" ]] || die "Missing snippet name for add"
            local target_scope="$scope"
            local found=$(find_snippet_scope_and_path "$name")
            local found_file="${found#*|}"
            if [[ -z "$target_scope" ]]; then
                target_scope=$(default_writable_scope)
            fi
            local file=$(snippet_file_path "$target_scope" "$name")
	    if [[ -n "$found_file" && "$found_file" != "$file" && ! -e "$file" ]] ; then
		cat "$found_file" > $file
	    fi
            mkdir -p "$(dirname "$file")"
            handle_text_file_command "$file" append "$@"
	    ;;
        add)
	    shift
            name="$1"
            shift
            [[ -n "$name" ]] || die "Missing snippet name for add"
            local target_scope="$scope"
            if [[ -z "$target_scope" ]]; then
                target_scope=$(default_writable_scope)
            fi
            local file
            file=$(snippet_file_path "$target_scope" "$name")
            mkdir -p "$(dirname "$file")"
            handle_text_file_command "$file" append "$@"
            ;;
        replace)
	    shift
            name="$1"
            shift
            [[ -n "$name" ]] || die "Missing snippet name for replace"
            local target_scope="$scope"
            if [[ -z "$target_scope" ]]; then
                target_scope=$(default_writable_scope)
            fi
            local file
            file=$(snippet_file_path "$target_scope" "$name")
            mkdir -p "$(dirname "$file")"
            handle_text_file_command "$file" replace "$@"
            ;;
        edit)
            shift
            name="$1"
            shift
            [[ -n "$name" ]] || die "Missing snippet name for edit"
            local target_scope="$scope"
            if [[ -z "$target_scope" ]]; then
                target_scope=$(default_writable_scope)
            fi
            local file
            file=$(snippet_file_path "$target_scope" "$name")
            if [[ ! -f "$file" ]]; then
                # If snippet does not exist, create empty file first
                mkdir -p "$(dirname "$file")"
                : > "$file"
            fi
            handle_text_file_command "$file" edit "$@"
            ;;
        delete)
	    shift
            name="$1"
	    shift
            [[ -n "$name" ]] || die "Missing snippet name for delete"
            if [[ -n "$scope" ]]; then
                local file
                file=$(snippet_file_path "$scope" "$name")
                if [[ -f "$file" ]]; then
                    rm -f "$file"
                    info "Deleted snippet '$name' from scope '$scope'"
                else
                    die "Snippet '$name' not found in scope '$scope'"
                fi
            else
                local found
                found=$(find_snippet_scope_and_path "$name") || die "Snippet '$name' not found in any scope"
                local found_scope="${found%%|*}"
                local found_file="${found#*|}"
                rm -f "$found_file"
                info "Deleted snippet '$name' from scope '$found_scope'"
            fi
            ;;
	"")
	    handle_snippet_command "list"
	    ;;
        *)
            # Default: treat $subcmd as snippet name
            local snippet_name="$subcmd"
	    shift # We shift it out here and then put it back a little later
            # Remaining args are $@
            if [[ $# -eq 0 ]]; then
		# No further args, default to show
		subcmd="show"
		set -- "$snippet_name"
            else
		# If first arg is "read" or "compose", treat as append
		if [[ "$1" == "read" || "$1" == "compose" ]]; then
                    subcmd="add"
		else
                    subcmd="add"
		fi
		set -- "$snippet_name" "$@"
            fi
	    if [[ -n "$scope" ]] ; then
		handle_snippet_command --scope "$scope" "$subcmd" "$@"
	    else
		handle_snippet_command "$subcmd" "$@"
	    fi
            ;;
    esac
}
