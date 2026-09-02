# Skill management
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

# Read description from SKILL.md header description field
read_skill_description() {
    local skill_md="$1"
    if [[ ! -f "$skill_md" ]]; then
        echo ""
        return
    fi
    awk '
    BEGIN {desc="" ; inheader=0}
    /^---/ {if (inheader==0) {inheader=1; next} else {inheader=0; exit}}
    inheader && /^description:[ \t]*(.*)/ {desc=substr($0, index($0,$2))}
    END {print desc}
    ' "$skill_md"
}

get_all_ordered_skill_names() {
    local type="$1"
    declare -A seen=()
    local sc
    for sc in "${SKILL_SEARCH_ORDER[@]}"; do
        local dir_list="${SKILL_DIRS[$sc]}" dir=""
        IFS=':' read -ra dirs <<< "$dir_list"
        for dir in "${dirs[@]}"; do
            [[ -d "$dir" ]] || continue
	    local d
            for d in "$dir"/*; do
                [[ -d "$d" ]] || continue
                if [[ -f "$d/SKILL.md" ]]; then
                    local skillname=$(basename "$d")
                    if [[ -z "${seen[$skillname]}" ]]; then
                        seen["$skillname"]=1
			if [[ "$type" == "file" ]] ; then
			    echo "$skillname $d/SKILL.md"
			else
			    echo "$skillname"
			fi
                    fi
                fi
            done
        done
    done
}

list_skills() {
    local scope="$1"
    local skillset_file="$2"
    local skillset_context_file="$3"
    local skillsdata="$(get_all_ordered_skill_names "file")"

    local allowed_glob=$(make_glob_from_file "$skillset_file")
    local memorized_glob=$(make_glob_from_file "$skillset_context_file")
    
    while IFS=' ' read -r skill skillfile; do
	if [[ -n $memorized_glob && $skill == $memorized_glob ]]; then
            if [[ -n $allowed_glob && $skill == $allowed_glob ]]; then
		printf '+ %s %s\n' "$skill" "$skillfile"
            else
		printf 'E %s %s\n' "$skill" "$skillfile"
            fi
	elif [[ -n $allowed_glob && $skill == $allowed_glob ]]; then
            printf '* %s %s\n' "$skill" "$skillfile"
	else
            printf '  %s %s\n' "$skill" "$skillfile"
	fi
    done <<< "$skillsdata"
}

generate_skillset_gen() {
    local scope="$1"
    local skillset_file="$2"
    local skillset_gen_file="$3"

    local skillsdata="$(get_all_ordered_skill_names "file")"
    local allowed_glob="$(make_glob_from_file "$skillset_file")"

    rm -f "$skillset_gen_file"
    if [[ -e "$skillset_file" ]] ; then
	: > "$skillset_gen_file"
	while IFS=' ' read -r skill skillfile; do
            if [[ -n $allowed_glob && $skill == $allowed_glob ]]; then
		desc=$(read_skill_description "$skillfile")
		echo "- $skill - $desc" >> "$skillset_gen_file"
	    fi
	done <<< "$skillsdata"
    fi
}

generate_skillset_context_gen() {
    local scope="$1"
    local skillset_context_file="$2"
    local skillset_context_gen_file="$3"

    local skillsdata="$(get_all_ordered_skill_names "file")"
    local memory_glob=$(make_glob_from_file "$skillset_context_file")
    
    rm -f "$skillset_context_gen_file"
    if [[ -e "$skillset_context_file" ]] ; then
	: > "$skillset_context_gen_file"
	while IFS=' ' read -r skill skillfile; do
            if [[ -n $memory_glob && $skill == $memory_glob ]]; then
		content=$(sed -n '/^---$/,/^---$/d; s/^#/###/g; p' "$skillfile")
		{
		    printf "## %s\n" "$skill"
                    echo "$content"
                    echo
		} >> "$skillset_context_gen_file"
	    fi
	done <<< "$skillsdata"
    fi
}

expand_allowed_skillset_context_file() {
    local scope="$1" skillset_file="$2" skillset_context_file="$3"
    local allow_glob="$(make_glob_from_file "$skillset_file")"
    local memory_glob="$(make_glob_from_file "$skillset_context_file")"
    local skills="$(get_all_ordered_skill_names "name")"
    rm -f "${skillset_context_file}"
    if [[ -e "$skillset_file" ]] ; then
	touch "${skillset_context_file}"
	while IFS=' ' read -r skill ; do
	    if [[ -n $allow_glob && $skill == $allow_glob ]]; then
		if [[ -n $memory_glob && $skill == $memory_glob ]]; then
		    echo $skill >> "${skillset_context_file}"
		fi
	    fi
	done <<< "$skills"
    fi
}

refresh_allowed_skillset_file() {
    local scope="$1" skillset_file="$2"
    local skillset_gen_file="${skillset_file%.txt}.gen"
    if [ ! -e "$skillset_file" ] ; then
	rm -f "$skillset_gen_file"
    else
	generate_skillset_gen "$scope" "$skillset_file" "$skillset_gen_file"
    fi
}

refresh_allowed_skillset_context_file() {
    local scope="$1" skillset_context_file="$2"
    local skillset_context_gen_file="${skillset_context_file%.txt}.gen"
    if [ ! -e "$skillset_context_file" ] ; then
	rm -f "$skillset_context_gen_file"
    else
	generate_skillset_context_gen "$scope" "$skillset_context_file" "$skillset_context_gen_file"
    fi
}

verify_skillset_files() {
    local scope="$1"
    local skillset_file="$2"
    local skillset_context_file="$3"
    local skillset_gen_file="${skillset_file%.txt}.gen"
    local skillset_context_gen_file="${skillset_context_file%.txt}.gen"
    local err=0
    if [[ ! -e "$skillset_file" && -e "$skillset_gen_file" ]] ; then
	warn "No skill allow definitions but skill list for scope $scope"
	err=1
    fi
    if [[ ! -e "$skillset_context_file" && -e "$skillset_context_gen_file" ]] ; then
	warn "No skill memory definitions but memorized skill instructions for scope $scope"
	err=1
    fi
    if [[ -e "$skillset_file" && ! -e "$skillset_gen_file" ]] ; then
	warn "Skill allow definitions but no skill list for scope $scope"
	err=1
    fi
    if [[ -e "$skillset_context_file" && ! -e "$skillset_context_gen_file" ]] ; then
	warn "Skill memory definitions but no memorized skill instructions for scope $scope"
	err=1
    fi
    if [[ $err == 0 ]] ; then
	if [[ -e "$skillset_file" ]] ; then
	    generate_skillset_gen "$scope" "$skillset_file" "${skillset_gen_file}.tmp"
	    if ! diff "$skillset_gen_file" "${skillset_gen_file}.tmp" > /dev/null ; then
		warn "Allowed skills list for '$scope' is out of sync with the available skills."
		diff -u "$skillset_gen_file" "${skillset_gen_file}.tmp"
		err=1
	    else
		notice "Allowed skills list for scope '$scope' is up to date"
	    fi
	fi
	if [[ -e "$skillset_context_file" ]] ; then
	    generate_skillset_context_gen "$scope" "$skillset_context_file" "${skillset_context_gen_file}.tmp"
	    if ! diff "$skillset_context_gen_file" "${skillset_context_gen_file}.tmp" > /dev/null ; then
		warn "Memorized skill instruction for scope '$scope' is out of sync with the available skills."
		diff -u "$skillset_context_gen_file" "${skillset_context_gen_file}.tmp"
		err=1
	    else
		notice "Memorized skill instructions for scope '$scope' is up to date"
	    fi
	fi
    fi
    return $err
}

# Expand wildcards
expand_skill_wildcards() {
    # To implement using make_glob and 
    local skillsdata="$(get_all_ordered_skill_names "name")"
    local glob="$(make_glob_from_var "$@")"
    
    while IFS=' ' read -r skill ; do
        if [[ -n $glob && $skill == $glob ]]; then
	    echo $skill
	fi
    done <<< "$skillsdata"
}

skill_usage() {
    cat <<EOF
USAGE

  maia skill [--scope <scope>] [--type <type>] <command> [<args>...]
     Manage skills
  maia skill --scope
     Show the scope for the current skill definitions

Manage LLM skills.

COMMANDS

  list
      List all discovered skills, marking allowed and loaded skills.

  show
      Show allowed skills and their descriptions.

  remember|add <skillname>...
      Add skill(s) to the loaded context.

  forget <skillname>...
      Remove skill(s) from the loaded context.

  append|allow [--remember] <skillname>...
      Append skill(s) to the allowed list. Wildcards supported.
      If --remember is given, also add to loaded context.

  replace [--remember] <skillname>...
      Replace allowed skills with specified ones. Wildcards supported.
      If --remember is given, also replace loaded context.

  clear
      Clear allowed skills list.

  run <skillname> <scriptname> [args...]
      Run a skill script directly. The result is not recorded in the conversation history.

  refresh
      Refresh cached skill metadata and prompt files.

  verify
      Verify consistency of skill definitions and caches.

  delete <skillname|wildcard>...
      Remove skill(s) from allowed list. Wildcards supported.

OPTIONS

  --scope <scope>
      Specify the scope to operate on. Valid: session, workspace, home, user, system, extra.

  --type <type>
      The types are allow (default) and memory.

  -h, --help
      Show this help message and exit.

NOTE

  <skillname> is handled as <text-or-file>:
    - a word
    - a "quoted text"
    - +command (compose, read, edit)
    - =filename (content of a file)
    - ++word (litteral +word)
    - ==word (litteral =word)
    - @snippet
  If multiple are provided they are appended as new lines (except for edit
  which opens the editor inline).

  --remember only add the skills as arguments, not skills read by read or compose.

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

handle_skill_command() {
    [[ "$1" =~ ^-h|--help$ ]] && skill_usage
    [[ "$2" =~ ^-h|--help$ ]] && skill_usage

    local type="allow"
    local scope=""
    local scopearg=""
    local prompt_type=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                skill_usage
                ;;
	    --type)
		shift
		type="$1"
		shift
		;;
            --scope)
                shift
                scope="$1"
                shift || true
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

    case "$type" in
	allow)
	    prompt_type="skillset"
	    ;;
	memory|context)
	    prompt_type="skillsetcontext"
	    ;;
	*)
	    die "Unknown skill type $type."
	    ;;
    esac

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

    if [[ -z "${SCOPE_DIRS[$scope]}" ]]; then
        die "Unknown scope '$scope'. Valid scopes: ${!SCOPE_DIRS[*]}"
    fi
    
    local subcmd="${1:-}"
    shift || true

    local skillset_file="${SCOPE_DIRS[$scope]}/skillset.txt"
    local skillset_context_file="${SCOPE_DIRS[$scope]}/skillsetcontext.txt"

    local filepath=""
    
    case "$type" in
	allow)
	    filepath="$skillset_file"
	    ;;
	memory|context)
	    filepath="$skillset_context_file"
	    ;;
	*)
	    :
	    ;;
    esac

    init_skill_search_dirs

    local remember=""
    case "$subcmd" in
	append|allow|replace)
            if [[ "$1" == "--remember" || "$1" == "--load" ]]; then
		if [[ "$prompt_type" == "skillsetcontext" ]] ; then
		    die "Options --type allow and --remember|--load are mutualy exclusive."
		fi
                shift
		remember=("$@")
            fi
	    if [[ "$subcmd" != "replace" ]] ; then
		mkdir -p "${SCOPE_DIRS[$scope]}"
		copy_over "$implicit_scope" "prompt_type" "$filepath"
	    fi
	    if [[ "$subcmd" == "allow" ]] ; then
		subcmd="append"
	    fi
	    ;;
	*)
	    :
	    ;;
    esac
    
    case "$subcmd" in
        list)
	    list_skills "$scope" "$skillset_file" "$skillset_context_file"
            ;;
        restrict)
            # Restrict skills from the allowed list
            if [[ ! -s "$skillset_file" ]]; then
                # Nothing to restrict if file does not exist, or if it is empty
                return 0
            fi
            # Read current allowed skills
	    mapfile -t current_skills_globs < "$skillset_file"
	    mapfile -t current_skills < <(expand_skill_wildcards "${current_skills_globs[@]}")

            # Expand wildcards for given patterns
            local matched_skills=()
            for pattern in "$@"; do
                # Convert wildcard to regex
                local regex_pattern="^${pattern//\*/.*}$"
                for skill in "${current_skills[@]}"; do
                    if [[ $skill =~ $regex_pattern ]]; then
                        matched_skills+=("$skill")
                    fi
                done
            done
            # Remove matched skills from current skills
            local new_skills=()
            for skill in "${current_skills[@]}"; do
                local skip=false
                for ms in "${matched_skills[@]}"; do
                    if [[ "$skill" == "$ms" ]]; then
                        skip=true
                        break
                    fi
                done
                if ! $skip; then
                    new_skills+=("$skill")
                fi
            done
            # Update the allowed skills file
            printf '%s\n' "${new_skills[@]}" > "$skillset_file"
            # Also clear skillset context if restrict is used
            rm -f "$skillset_context_file"
            refresh_allowed_skillset_file "$scope" "$skillset_file"
            expand_allowed_skillset_context_file "$scope" "$skillset_file" "$skillset_context_file"
            refresh_allowed_skillset_context_file "$scope" "$skillset_context_file"
            ;;
	view|"")
	    # Expand allowed wildcards to explicit allowed skills
	    if [[ "$1" == "--expand" ]]; then
                mapfile -t allowed_patterns < <(prompt_for_scope "$scope" "$prompt_type")
                expand_skill_wildcards "${allowed_patterns[@]}" | uniq
	    else
		prompt_for_scope "$scope" "$prompt_type"
	    fi
	    ;;
        show)
	    echo "Allowed skills:"
	    echo "---------------"
	    prompt_for_scope "$scope" "skillset"
	    echo
	    echo "Memorized skills:"
	    echo "-----------------"
	    prompt_for_scope "$scope" "skillsetcontext"
	    echo
	    echo "Allowed skill list:"
	    echo "-------------------"
	    prompt_for_scope "$scope" "skillset" "gen"
	    echo
	    echo "Memorized skill information:"
	    echo "----------------------------"
	    prompt_for_scope "$scope" "skillsetcontext" "gen"
            ;;
        append|allow|edit|read|compose|replace|clear|delete)
	    # seed on first append
	    if [[ "$subcmd" == "allow" ]] ; then
		subcmd="append"
	    fi
	    handle_text_file_command "$filepath" "$subcmd" "$@"
	    deduplicate_files "$filepath"
	    if [[ "$prompt_type" == "skillset" ]] ; then
		refresh_allowed_skillset_file "$scope" "$skillset_file"
		if [[ "$subcmd" == "delete" ]] ; then
		    handle_text_file_command "$skillset_context_file" delete > /dev/null 2>&1
		fi
	    fi
	    expand_allowed_skillset_context_file "$scope" "$skillset_file" "$skillset_context_file"
	    deduplicate_files "$skillset_context_file"
	    refresh_allowed_skillset_context_file "$scope" "$skillset_context_file"
            ;;
        run)
            if [[ $# -lt 2 ]]; then
                die "Usage: maia skill run <skillname> <scriptname> [args...]"
            fi
            skill_execute "$scope" "$@"
            ;;
        refresh)
	    deduplicate_files "$skillset_file"
	    refresh_allowed_skillset_file "$scope" "$skillset_file"
	    expand_allowed_skillset_context_file "$scope" "$skillset_file" "$skillset_context_file"
	    deduplicate_files "$skillset_context_file"
	    refresh_allowed_skillset_context_file "$scope" "$skillset_context_file"
            ;;
        verify)
            verify_skillset_files "$scope" "$skillset_file" "$skillset_context_file"
            ;;
        remember|add)
            if [[ $# -lt 1 ]]; then
                die "Usage: maia skill remember|add <skillname>..."
            fi
	    remember=("$@")
	    subcmd=append
            ;;
        forget)
	    # TODO
            if [[ $# -lt 1 ]]; then
                die "Usage: maia skill forget <skillname>..."
            fi
            if [[ ! -f "$skillset_context_file" ]]; then
                return 0
            fi
            local expanded=$(expand_skill_wildcards "$@")
            # Remove from loaded context
            local tmpfile=$(mktemp)
            grep -vxF -f <(printf '%s\n' "${expanded[@]}") "$skillset_context_file" > "$tmpfile"
            mv "$tmpfile" "$skillset_context_file"
	    refresh_allowed_skillset_context_file "$scope" "$skillset_context_file"
            ;;
        *)
            die "Unknown skill subcommand: $subcmd"
            ;;
    esac
    if [[ -n "$remember" ]] ; then
	copy_over "$implicit_scope" "skillsetcontext" "$skillset_context_file"
	handle_text_file_command "$skillset_context_file" "$subcmd" "${remember[@]}"
	expand_allowed_skillset_context_file "$scope" "$skillset_file" "$skillset_context_file"
	deduplicate_files "$skillset_context_file"
	refresh_allowed_skillset_context_file "$scope" "$skillset_context_file"
    fi
}
