#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

group_usage() {
    cat <<'EOF'
USAGE

  maia group <command> [<name>] [<session>...]

Manage named groups of sessions. Groups are stored as plain-text files under
$MAIA_HOME/groups/session (or the configured MAIA home directory), with one session
name per line.

COMMANDS

  list|ls
    List all groups.

  create <name>
    Create an empty group.

  show [--json] [<name>...]
    Show the sessions in the specified groups, or all groups if no name is given.
    --json outputs an array of groups, each with a name and sessions array.

  edit <name>
    Edit a group's session list.

  add <name> [<session>...]
    Add session names to a group. If no session is given, do nothing.

  remove <name> [<session>...]
    Remove session names from a group. If no session is given, do nothing.

  change <name> <old-session> <new-session>
    Change a session name in a group.

  replace <name> [<session>...]
    Replace a group's session list with the given names.

  clear <name>
    Remove all sessions from a group.

  delete <name>
    Delete a group.

EOF
    exit 0
}

group_directory() {
    resolve_group_directory session
}

group_validate_name() {
    validate_group_name "$1"
}

group_file() {
    resolve_group_file session "$1"
}

group_show_json() {
    local dir="$(group_directory)"
    [[ -d "$dir" ]] || { printf '[]\n'; return 0; }

    local f
    for f in "$dir"/*.txt; do
        [[ -f "$f" ]] || continue
        local name="$(basename "$f" .txt)"
        jq -n --arg name "$name" --rawfile sessions "$f" \
            '{name: $name, sessions: ($sessions | split("\n") | map(select(length > 0)))}'
    done | jq -s '.'
}

handle_group_command() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && group_usage
    local cmd="${1:-list}"
    shift || true

    case "$cmd" in
        list|ls)
            [[ $# -eq 0 ]] || die "Usage: maia group list"
            local dir="$(group_directory)"
            [[ -d "$dir" ]] || return 0
            local f
            for f in "$dir"/*.txt; do
                [[ -f "$f" ]] || continue
                printf '%s\n' "$(basename "$f" .txt)"
            done
            ;;
        create)
            [[ $# -eq 1 ]] || die "Usage: maia group create <name>"
            local name="$1"
            local file="$(group_file "$name")"
            [[ ! -e "$file" ]] || die "Group '$name' already exists."
            mkdir -p "$(dirname "$file")" || die "Unable to create group directory."
            : > "$file" || die "Unable to create group '$name'."
            notice "Created group '$name'."
            ;;
        show)
            local json=false
            if [[ "${1:-}" == "--json" ]]; then
                json=true
                shift
            fi
            local -a names=("$@")

            if [[ "$json" == true ]]; then
                if ((${#names[@]} == 0)); then
                    group_show_json
                else
                    local -a groups_json=()
                    local name
                    for name in "${names[@]}"; do
                        local file="$(group_file "$name")"
                        [[ -f "$file" ]] || die "Group '$name' does not exist."
                        groups_json+=("$(jq -n --arg name "$name" --rawfile sessions "$file" \
                            '{name: $name, sessions: ($sessions | split("\n") | map(select(length > 0)))}')")
                    done
                    printf '%s\n' "${groups_json[@]}" | jq -s '.'
                fi
            elif ((${#names[@]} > 0)); then
                local name
                for name in "${names[@]}"; do
                    local file="$(group_file "$name")"
                    [[ -f "$file" ]] || die "Group '$name' does not exist."
                    printf '%s:\n' "$name"
                    handle_text_file_command "$file" show | sed 's/^/  /'
                done
            else
                local dir="$(group_directory)"
                [[ -d "$dir" ]] || return 0
                local f
                for f in "$dir"/*.txt; do
                    [[ -f "$f" ]] || continue
                    local group_name="$(basename "$f" .txt)"
                    printf '%s:\n' "$group_name"
                    handle_text_file_command "$f" show | sed 's/^/  /'
                done
            fi
            ;;
        edit)
            [[ $# -eq 1 ]] || die "Usage: maia group edit <name>"
            local name="$1"
            local file="$(group_file "$name")"
            [[ -f "$file" ]] || die "Group '$name' does not exist."
            handle_text_file_command "$file" edit
            deduplicate_files "$file"
            ;;
        add|remove)
            [[ $# -ge 1 ]] || die "Usage: maia group $cmd <name> [<session>...]"
            local name="$1"
            shift
            local file="$(group_file "$name")"
            [[ -f "$file" ]] || die "Group '$name' does not exist."
            # A missing session argument is intentionally a quiet no-op.
            [[ $# -gt 0 ]] || return 0
            if [[ "$cmd" == "add" ]]; then
                local session
                for session in "$@"; do
                    [[ -n "$session" ]] || continue
                    printf '%s\n' "$session" >> "$file" || die "Unable to update group '$name'."
                done
                deduplicate_files "$file"
            else
                local tmp="$(mktemp "${file}.tmp.XXXXXX")" || die "Unable to update group '$name'."
                local line
                while IFS= read -r line || [[ -n "$line" ]]; do
                    local remove=false
                    local remove_session
                    for remove_session in "$@"; do
                        if [[ "$line" == "$remove_session" ]]; then
                            remove=true
                            break
                        fi
                    done
                    [[ "$remove" == true ]] || printf '%s\n' "$line" >> "$tmp"
                done < "$file"
                mv -- "$tmp" "$file" || { rm -f -- "$tmp"; die "Unable to update group '$name'."; }
            fi
            ;;
        change)
            [[ $# -eq 3 ]] || die "Usage: maia group change <name> <old-session> <new-session>"
            local name="$1"
            local file="$(group_file "$name")"
            [[ -f "$file" ]] || die "Group '$name' does not exist."
            handle_text_file_command "$file" change "$2" "$3"
            deduplicate_files "$file"
            ;;
        replace)
            [[ $# -ge 1 ]] || die "Usage: maia group replace <name> [<session>...]"
            local name="$1"
            shift
            local file="$(group_file "$name")"
            [[ -f "$file" ]] || die "Group '$name' does not exist."
            handle_text_file_command "$file" replace "$@"
            deduplicate_files "$file"
            ;;
        clear)
            [[ $# -eq 1 ]] || die "Usage: maia group clear <name>"
            local name="$1"
            local file="$(group_file "$name")"
            [[ -f "$file" ]] || die "Group '$name' does not exist."
            handle_text_file_command "$file" clear
            ;;
        delete)
            [[ $# -eq 1 ]] || die "Usage: maia group delete <name>"
            local name="$1"
            local file="$(group_file "$name")"
            [[ -f "$file" ]] || die "Group '$name' does not exist."
            rm -f -- "$file" || die "Unable to delete group '$name'."
            notice "Deleted group '$name'."
            ;;
        "")
            group_usage
            ;;
        *)
            group_usage
            ;;
    esac
}
