# Instruction management
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

### Event handling

list_instructions() {
    local scope="$1"
    local instructionset_file="$2"
    local instructionsdata="$(get_all_ordered_instruction_names "file")"

    local memorized_glob=$(make_glob_from_file "$instructionset_file")
    
    while IFS=' ' read -r instruction instructionfile; do
	if [[ -n $memorized_glob && $instruction == $memorized_glob ]]; then
	    printf '* %s %s\n' "$instruction" "$instructionfile"
	else
	    # TODO: Implement autoload information
            printf '  %s %s\n' "$instruction" "$instructionfile"
	fi
    done <<< "$instructionsdata"
}

expand_instructionset_file() {
    local scope="$1" instructionset_file="$2"
    local memory_glob="$(make_glob_from_file "$instructionset_file")"
    local instructions="$(get_all_ordered_instruction_names "name")"
    rm -f "${instructionset_file}"
    touch "${instructionset_file}"
    while IFS=' ' read -r instruction ; do
	if [[ -n $memory_glob && $instruction == $memory_glob ]]; then
	    echo $instruction >> "${instructionset_file}"
	fi
    done <<< "$instructions"
}

# Expand wildcards
expand_instruction_wildcards() {
    local instructionsdata="$(get_all_ordered_instruction_names "name")"
    local glob="$(make_glob_from_var "$@")"

    while IFS=' ' read -r instruction ; do
	if [[ -n $glob && $instruction == $glob ]]; then
	    echo $instruction
	fi
    done <<< "$instructionsdata"
}

instruction_usage() {
    cat <<EOF
USAGE

  maia instruction [--scope <scope>] <command> [<args>...]
     Manage instructions
  maia instruction --scope
     Show the scope for the current instruction definitions

Manage LLM instructions.

COMMANDS

  list
      List all discovered instructions, marking loaded instructions.

  show
      Show loaded instructions and their descriptions.

  append|remember|add <instructionname>...
      Append instruction(s) to the loaded list. Wildcards supported.

  replace <instructionname>...
      Replace loaded instructions with specified ones. Wildcards supported.

  forget <instructionname>...
      Remove instruction(s) from the loaded context.

  clear
      Clear loaded instructions list.

  delete
      Remove the loaded instruction list.

OPTIONS

  --scope <scope>
      Specify the scope to operate on. Valid: session, workspace, home, user, system, extra.

  -h, --help
      Show this help message and exit.

NOTE

  <instructionname> is handled as <text-or-file>:
    - a word
    - a "quoted text"
    - +command (compose, read, edit)
    - =filename (content of a file)
    - ++word (litteral +word)
    - ==word (litteral =word)
    - @snippet
  If multiple are provided they are appended as new lines (except for edit
  which opens the editor inline).

EOF
    exit 0
}

copy_over() {
    local implicit_scope="$1"
    local prompt_type="$2"
    local filepath="$3"
    if [[ ! -f "$filepath" ]]; then
	local msg=$(prompt_for_scope "$implicit_scope" "prompt_type")
	if [[ -z "$msg" ]] ; then
	    touch "$filepath"
	else
	    echo "$msg" > "$filepath"
	fi
    fi
}

handle_instruction_command() {
    [[ "$1" =~ ^-h|--help$ ]] && instruction_usage
    [[ "$2" =~ ^-h|--help$ ]] && instruction_usage

    local scope=""
    local scopearg=""
    local prompt_type="instructionset"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                instruction_usage
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

    local subcmd="${1:-}"
    shift || true

    # default scope if none given
    determine_implicit_scope "$prompt_type"
    if [[ "$scopearg" = "yes" && -z "$scope" ]] ; then
        echo "$implicit_scope"
        return
    fi

    # Special default scope handling
    case "$subcmd" in
	list)
	    scope="$implicit_scope"
	    ;;
        refresh|verify|edit)
	    if [[ -z "$scope" && "$implicit_scope" != "default" && "$implicit_scope" != "system" ]]; then
		scope="$implicit_scope"
	    fi
	    ;;
	*)
	    :
	    ;;
    esac

    if [[ -z "$scope" ]]; then
        scope="session"
    fi

    validate_scope "$scope"
	
    local filepath="${SCOPE_DIR[$scope]}/instructionset.txt"

    init_instruction_search_dirs

    local remember=""
    case "$subcmd" in
	append|remember|add)
	    mkdir -p "${SCOPE_DIR[$scope]}"
	    copy_over "$implicit_scope" "$prompt_type" "$filepath"
	    ;;
	*)
	    :
	    ;;
    esac
    
    case "$subcmd" in
        list)
	    list_instructions "$scope" "$filepath"
            ;;
	view|"")
	    # Expand allowed wildcards to explicit allowed instructions
	    if [[ "$1" == "--expand" ]]; then
                mapfile_from_command patterns prompt_for_scope "$scope" "$prompt_type"
                expand_instruction_wildcards "${patterns[@]}" | sort -u
	    else
		prompt_for_scope "$scope" "$prompt_type"
	    fi
	    ;;
        show)
	    echo "Memorized instructions:"
	    echo "-----------------"
	    prompt_for_scope "$scope" "instructionset"
            ;;
        append|remember|add|edit|replace|clear|clearnonotice|delete)
	    # seed on first append
	    if [[ "$subcmd" == "remember" || "$subcmd" == "add" ]] ; then
		subcmd="append"
	    fi
	    handle_text_file_command "$filepath" "$subcmd" "$@"
	    deduplicate_files "$filepath"
	    ;;
        forget)
            # Forget instructions
            if [[ ! -s "$filepath" ]]; then
                # Nothing to forget if file does not exist, or if it is empty
                return 0
            fi
            # Read current instructions
	    mapfile -t current_instructions_globs < "$filepath"
	    mapfile_from_command current_instructions expand_instruction_wildcards "${current_instructions_globs[@]}"

            # Expand wildcards for given patterns
            local matched_instructions=()
            for pattern in "$@"; do
                # Convert wildcard to regex
                local regex_pattern="^${pattern//\*/.*}$"
                for instruction in "${current_instructions[@]}"; do
                    if [[ $instruction =~ $regex_pattern ]]; then
                        matched_instructions+=("$instruction")
                    fi
                done
            done
            # Remove matched instructions from current instructions
            local new_instructions=()
            for instruction in "${current_instructions[@]}"; do
                local skip=false
                for ms in "${matched_instructions[@]}"; do
                    if [[ "$instruction" == "$ms" ]]; then
                        skip=true
                        break
                    fi
                done
                if ! $skip; then
                    new_instructions+=("$instruction")
                fi
            done
            # Update the allowed instructions file
            printf '%s\n' "${new_instructions[@]}" > "$filepath"
            ;;
        *)
            die "Unknown instruction subcommand: $subcmd"
            ;;
    esac
}
