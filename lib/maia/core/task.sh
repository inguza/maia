# Task management
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

### Event handling

list_tasks() {
    local scope="$1"
    local taskset_file="$2"
    local tasksdata="$(get_all_ordered_task_names "file")"

    local memorized_glob=$(make_glob_from_file "$taskset_file")
    
    while IFS=' ' read -r task taskfile; do
	if [[ -n $memorized_glob && $task == $memorized_glob ]]; then
	    printf '* %s %s\n' "$task" "$taskfile"
	else
	    # TODO: Implement autoload information
            printf '  %s %s\n' "$task" "$taskfile"
	fi
    done <<< "$tasksdata"
}

show_tasks() {
    local scope="$1"
    local taskset_file="$2"
    local tasksdata="$(get_all_ordered_task_names "file")"

    local memorized_glob=$(make_glob_from_file "$taskset_file")
    
    while IFS=' ' read -r task taskfile; do
	if [[ -n $memorized_glob && $task == $memorized_glob ]]; then
	    myl_pretty "$taskfile" "task"
	fi
    done <<< "$tasksdata"
}

expand_taskset_file() {
    local scope="$1" taskset_file="$2"
    local memory_glob="$(make_glob_from_file "$taskset_file")"
    local tasks="$(get_all_ordered_task_names "name")"
    rm -f "${taskset_file}"
    touch "${taskset_file}"
    while IFS=' ' read -r task ; do
	if [[ -n $memory_glob && $task == $memory_glob ]]; then
	    echo $task >> "${taskset_file}"
	fi
    done <<< "$tasks"
}

# Expand wildcards
expand_task_wildcards() {
    local tasksdata="$(get_all_ordered_task_names "name")"
    local glob="$(make_glob_from_var "$@")"

    while IFS=' ' read -r task ; do
	if [[ -n $glob && $task == $glob ]]; then
	    echo $task
	fi
    done <<< "$tasksdata"
}

# NOT good enough
find_task_index() {
    local basedir="$1"
    local prefix="$2"
    local index=1
    # Match any file with this pattern
    # TODO: This has a race condition between check and touch
    while [[ -f "$basedir/${prefix}-${index}.myl" ]] ; do
        ((index++))
    done
    mkdir -p "$basedir"
    touch "$basedir/${prefix}-${index}.myl"
    echo "$index"
}

find_task_file() {
    local task="$1"
    local type
    local tname
    local index
    if [[ "$task" =~ ^task-([a-z]+)-([a-zA-Z0-9_]+)-([0-9]+)$ ]] ; then
	type="shared"
	scope="${BASH_REMATCH[1]}"
	tname="${BASH_REMATCH[2]}"
	index="${BASH_REMATCH[3]}"
    elif [[ "$task" =~ ^task-([0-9]+)$ ]] ; then
	type="private"
	scope="session"
	tname="$(resolve_session_name)"
	index="${BASH_REMATCH[1]}"
    else
	die "Unknown task type."
    fi
    if [[ ! -v TASK_DIR["$scope"] ]] ; then
	die "Scope '$scope' not allowed for task '$task'."
    fi
    local path="${TASK_DIR[$scope]}"
    if [[ -z "$path" ]] ; then
	die "Scope '$scope' not available for task '$task'."
    fi
    local ppath="$(dirname "$path")"
    if [[ ! -d "$ppath" ]] ; then
	die "Scope '$scope' not available for task '$task'."
    fi
    local file="$path/${type}-$index.myl"
    printf '%s' "$file"
}

task_usage() {
    cat <<EOF
USAGE

  maia task [--scope <scope>] <command> [<args>...]
     Manage tasks

Manage tasks.

COMMANDS

  create [--private|--shared] <description line 1> [<...>]
      Create a task. Not remembered immediately since tasks are by
      default for work to be done later.

  remove <taskname>...
      Delete and forget the task.

  mark <taskname> <status> <version>
      Set the status of a task to <status>.

  report <taskname> <report> <version>
      Report progress for <taskname>.

  list
      List all tasks, marking loaded tasks.

  show
      Show loaded tasks and their descriptions.

  append|remember|add <taskname>...
      Append task(s) to the loaded list. Wildcards supported.

  replace <taskname>...
      Replace loaded tasks with specified ones. Wildcards supported.

  forget <taskname>...
      Remove task(s) from the loaded context.

  clear
      Clear loaded tasks list.

  delete
      Remove the loaded task list.

OPTIONS

  --scope <scope>
      Specify the scope to operate on. Valid: session, workspace, profile.
      Applicable to create and remove only.

  -h, --help
      Show this help message and exit.

NOTE

  <taskname> is handled as <text-or-file>:
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

handle_task_command() {
    [[ "$1" =~ ^-h|--help$ ]] && task_usage
    [[ "$2" =~ ^-h|--help$ ]] && task_usage

    local scope=""
    local scopearg=""
    local prompt_type="taskset"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                task_usage
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
	list|view|show|append|remember|add|edit|replace|clear|clearnonotice|delete|forget|"")
	    scope="session"
	    ;;
	*)
	    :
	    ;;
    esac

    if [[ -z "$scope" ]]; then
        scope="session"
    fi

    validate_scope "$scope"
	
    local filepath="${SCOPE_DIR[$scope]}/taskset.txt"

    init_task_search_dirs

    case "$subcmd" in
	create)
	    local type="private"
	    if [[ "$1" == "--private" ]] ; then
		type="private"
		shift
	    elif [[ "$1" == "--shared" ]] ; then
		type="shared"
		shift
	    fi
	    if [[ -z "$1" ]] ; then
		die "Task description not provided."
	    fi
	    if [[ "$type" == "private" && "$scope" != "session" ]] ; then
		die "Scope '$scope' not allowed for $type tasks."
	    fi
	    if [[ ! -v TASK_DIR["$scope"] ]] ; then
		die "Scope '$scope' not allowed for tasks."
	    fi
	    local path="${TASK_DIR[$scope]}"
	    if [[ -z "$path" ]] ; then
		die "Scope '$scope' not available."
	    fi
	    local ppath="$(dirname "$path")"
	    if [[ ! -d "$ppath" ]] ; then
		die "Scope '$scope' not available."
	    fi
	    local index="$(find_task_index "$path" "${type}" ".myl")"
	    local file="$path/${type}-$index.myl"
	    local name
	    if [[ "$type" == "private" ]] ; then
		name="task-$index"
	    else
		local tname="$(resolve_${scope}_name)"
		name="task-${scope}-${tname}-${index}"
	    fi
	    myl_add "$file" 'task' "$name"
	    myl_add "$file" 'status' 'new'
	    myl_add "$file" 'version' '1'
	    myl_add "$file" 'description' "$@"
	    echo "" >> "$file"
	    myl_add "$file" 'progress'
	    notice "Task $name created. [$file]"
	    echo "$name"
	    handle_task_command remember "$name"
	    ;;
	remove)
	    local task
	    for task in "$@" ; do
		local file="$(find_task_file "$task")"
		rm -f "$file"
		notice "Task $task removed."
		handle_task_command forget "$name"
	    done
	    ;;
	mark)
	    if [[ -z "$1" ]] ; then
		die "Empty task id."
	    fi
	    local task="$1"
	    if [[ -z "$2" ]] ; then
		die "Empty task status."
	    fi
	    if [[ -z "$3" ]] ; then
		die "Empty version."
	    fi
	    local file="$(find_task_file "$task")"
	    if [[ -z "$file" || ! -f "$file" ]] ; then
		die "Task '$task' not found."
	    fi
	    local version="$(myl_get "$file" "version")"
	    if [[ "$version" != "$3" ]] ; then
		die "Task version mismatch. The provided version '$3' is not the same as the required version '$version'."
	    fi
	    myl_update "$file" "status" "$2"
	    myl_update "$file" "version" "$((version + 1))"
	    ;;
	report)
	    if [[ -z "$1" ]] ; then
		die "Empty task id."
	    fi
	    local task="$1"
	    if [[ -z "$2" ]] ; then
		die "Empty task status."
	    fi
	    if [[ -z "$3" ]] ; then
		die "Empty version."
	    fi
	    local file="$(find_task_file "$task")"
	    if [[ -z "$file" || ! -f "$file" ]] ; then
		die "Task '$task' not found."
	    fi
	    local version="$(myl_get "$file" "version")"
	    if [[ "$version" != "$3" ]] ; then
		die "Task version mismatch. The provided version '$3' is not the same as the required version '$version'."
	    fi
	    myl_append "$file" "progress" "$2"
	    myl_update "$file" "version" "$((version + 1))"
	    ;;
        list)
	    list_tasks "$scope" "$filepath"
            ;;
	
	view|"")
	    # Expand allowed wildcards to explicit allowed tasks
	    if [[ "$1" == "--expand" ]]; then
                mapfile_from_command patterns prompt_for_scope "$scope" "$prompt_type"
                expand_task_wildcards "${patterns[@]}" | sort -u
	    else
		prompt_for_scope "$scope" "$prompt_type"
	    fi
	    ;;
        show)
	    echo "Tasks:"
	    echo "------"
	    get_all_ordered_task_names "list"
	    echo ""
	    echo "Memorized tasks:"
	    echo "----------------"
	    prompt_for_scope "$scope" "taskset"
	    echo ""
	    echo "Task memory:"
	    echo "------------"
	    echo ""
	    show_tasks "$scope" "$filepath"
	    echo ""
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
            # Forget tasks
            if [[ ! -s "$filepath" ]]; then
                # Nothing to forget if file does not exist, or if it is empty
                return 0
            fi
            # Read current tasks
	    mapfile -t current_tasks_globs < "$filepath"
	    mapfile_from_command current_tasks expand_task_wildcards "${current_tasks_globs[@]}"

            # Expand wildcards for given patterns
            local matched_tasks=()
            for pattern in "$@"; do
                # Convert wildcard to regex
                local regex_pattern="^${pattern//\*/.*}$"
                for task in "${current_tasks[@]}"; do
                    if [[ $task =~ $regex_pattern ]]; then
                        matched_tasks+=("$task")
                    fi
                done
            done
            # Remove matched tasks from current tasks
            local new_tasks=()
            for task in "${current_tasks[@]}"; do
                local skip=false
                for ms in "${matched_tasks[@]}"; do
                    if [[ "$task" == "$ms" ]]; then
                        skip=true
                        break
                    fi
                done
                if ! $skip; then
                    new_tasks+=("$task")
                fi
            done
            # Update the allowed tasks file
            printf '%s\n' "${new_tasks[@]}" > "$filepath"
            ;;
        *)
            die "Unknown task subcommand: $subcmd"
            ;;
    esac
}
