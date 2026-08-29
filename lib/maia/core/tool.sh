#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

# Load all discovered tool definitions into an associative array keyed by name,
# respecting scope priority (first found wins).
# Output JSON array of tool definitions (merged)
# Important! init_tool_search_dirs must be called prior to this
load_all_tool_defs() {
    local files=()
    local scope
    for scope in "${TOOL_SEARCH_ORDER[@]}"; do
        local dir_list="${TOOL_DIRS[$scope]}"
        IFS=":" read -ra dirs <<< "$dir_list"
        for dir in "${dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                local file
                for file in "$dir"/*"$TOOLSET_DEF_EXT"; do
                    [[ -f "$file" ]] && files+=("$file")
                done
            fi
        done
    done
    # Output JSON array of all tools (flatten into a single array)
    jq -n '
        [inputs | .[] | . + {source: input_filename}]
    ' "${files[@]}"
}

# Helper: build jq filter from array of regex patterns
build_list_filter_from_patterns() {
    local allowed_tools_list_file="$1"
    local patterns=()

    if [ -e "$allowed_tools_list_file" ] ; then
	while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            patterns+=("$line")
	done < "$allowed_tools_list_file"
    fi

    printf '%s\n' "${patterns[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))'
}

list_tools() {
    # Load all tools}
    init_tool_search_dirs
    local all_tools_json=$(load_all_tool_defs)
    local scope="$1"
    local allowed_tools_list_file="$2"

    # Default to list all tools
    local patterns_json="$(build_list_filter_from_patterns "$allowed_tools_list_file")"
    # Deduplicate tools by name (keep last occurrence)
    local deduped_tools_json=$(jq '
        reduce .[] as $item ({}; .[$item.name] = $item) | [.[]]
    ' <<< "$all_tools_json")

    # Output list with allowed mark
    jq -r --argjson patterns "$patterns_json" '
      def glob_to_regex:
        "^" +
	(gsub("\\."; "\\.")
	| gsub("\\*"; ".*")
	| gsub("\\?"; ".")) +
	"$";

      def allowed_filter:
        .name as $name |
        any($patterns[];
	  . as $pattern |
	  $name | test($pattern | glob_to_regex)
	);

      .[] |
      if allowed_filter
      then "* " + .name + "   (" + .source + ")"
      else "  " + .name + "   (" + .source + ")"
      end
    ' <<< "$deduped_tools_json"
}
   
# IMPOPRTANT! init_tool_search_dirs
generate_allowed_toolset_def_file() {
    local allowed_tools_list_file="$1"
    local allowed_tools_def_file="$2"
    # Important to call this because it is used by load_all_tool_defs below
    init_tool_search_dirs
    
    local all_tool_defs_json=$(load_all_tool_defs)
    local patterns_json="$(build_list_filter_from_patterns "$allowed_tools_list_file")"

    # We match the names against the regexp and then for the matched ones we keep only the last if there are
    # several with the same name.
    # This uses the object index method that overwrites earlier entries
    jq --argjson patterns "$patterns_json" '
      def glob_to_regex:
        "^" +
	(gsub("\\."; "\\.")
	| gsub("\\*"; ".*")
	| gsub("\\?"; ".")) +
	"$";

  [
    .[] |
    select(
      .name as $name |
      any($patterns[];
        . as $pattern |
        $name | test($pattern | glob_to_regex)
      )
    )
  ]
  |
  reduce .[] as $item (
    {};
    .[$item.name] = $item
  )
  | [.[]]
' <<< "$all_tool_defs_json" > "$allowed_tools_def_file"
}

tool_instr_dir() {
    local tool_instr="$1"
    local tool_search_path="$2"
    # Find full path to executable without relying on PATH for security reasons
    local tool_instr="${tool_instr%% *}"
    local tool_instr_dir=""
    IFS=: read -ra dirs <<< "$tool_search_path"
    for d in "${dirs[@]}"; do
	if [[ -e "$d/$tool_instr" ]]; then
	    tool_instr_dir="$d"
	    break
	fi
    done
    printf "%s" "$tool_instr_dir"
}

generate_allowed_tools_instr_file() {
    local allowed_tools_list_file="$1"
    local allowed_tools_instr_file="$2"
    # Important to call this because it is used by load_all_tool_defs below
    init_tool_search_dirs
    local all_tool_defs_json=$(load_all_tool_defs)
    local patterns_json="$(build_list_filter_from_patterns "$allowed_tools_list_file")"
    local instruction_files=$(jq -r --argjson patterns "$patterns_json" '
      def glob_to_regex:
        "^" +
	(gsub("\\."; "\\.")
	| gsub("\\*"; ".*")
	| gsub("\\?"; ".")) +
	"$";

      [
        .[] |
	select(
	  .name as $name |
	  any($patterns[];
	    . as $pattern |
	    $name | test($pattern | glob_to_regex)
	  )
	) | .instructions[]?
      ] | unique[]
      ' <<< "$all_tool_defs_json")
    : > "$allowed_tools_instr_file"
    local tool_search_path=$(build_tool_search_path)

    while IFS= read -r tool_instr_file; do
        [[ -z "$tool_instr_file" ]] && continue

	local tool_instr_dir="$(tool_instr_dir "${tool_instr_file}" "$tool_search_path")"
	if [[ -z "$tool_instr_dir" ]]; then
	    warn "Tool instruction file $tool_instr_file not found."
	    continue
	else
	    cat "$tool_instr_dir/$tool_instr_file" >> "$allowed_tools_instr_file"
	fi
    done <<< "$instruction_files"
}

# Refresh: regenerate tools.json based on the tools.txt file
# This merges all discovered .td files and allowed tools state per scope
refresh_allowed_toolset_files() {
    local scope="$1"
    local allowed_tools_list_file="$2"
    local allowed_tools_def_file="${allowed_tools_list_file%.txt}.json"
    local allowed_tools_instr_file="${allowed_tools_list_file%set.txt}_instr.txt"
    if [ ! -e "$allowed_tools_list_file" ] ; then
	rm -f "$allowed_tools_def_file"
	rm -f "$allowed_tools_instr_file"
    else
	generate_allowed_toolset_def_file "$allowed_tools_list_file" "${allowed_tools_def_file}"
	generate_allowed_tools_instr_file "$allowed_tools_list_file" "${allowed_tools_instr_file}"
	info "Refreshed allowed toolset for scope '$scope'"
    fi
}

# Verify: check that allowed tool definitions are current with discovered .td files for scope
# Optionally for a specific function pattern
verify_tools_def_file() {
    local scope="$1"
    local allowed_tools_list_file="$2"
    local allowed_tools_def_file="${allowed_tools_list_file%.txt}.json"
    local allowed_tools_instr_file="${allowed_tools_list_file%set.txt}_instr.txt"
    local err=0
    if [ ! -e "$allowed_tools_list_file" ] ; then
	if [ -e "$allowed_tools_def_file" ] ; then
	    warn "No tool definitions but toolset JSON file exist for $scope"
	    err=1
	fi
	if [ -e "$allowed_tools_instr_file" ] ; then
	    warn "No tool instructions but toolset JSON file exist for $scope"
	    err=1
	fi
    else
	if [ ! -e "$allowed_tools_def_file" ] ; then
	    warn "Tool definitions but no toolset JSON file exist for $scope"
	    err=1
	else
	    generate_allowed_toolset_def_file "$allowed_tools_list_file" "${allowed_tools_def_file}.tmp"
	    if ! diff "$allowed_tools_def_file" "${allowed_tools_def_file}.tmp" > /dev/null ; then
		warn "Allowed toolset for scope '$scope' is out of sync with the available tools."
		diff -u "$allowed_tools_def_file" "${allowed_tools_def_file}.tmp"
		err=1
	    else
		notice "Allowed toolset JSON cache for scope '$scope' is up to date"
	    fi
	fi
	if [ ! -e "$allowed_tools_instr_file" ] ; then
	    warn "Tool definitions but no tool instructions file exist for $scope"
	    err=1
	else
	    generate_allowed_tools_instr_file "$allowed_tools_list_file" "${allowed_tools_instr_file}.tmp"
	    if ! diff "$allowed_tools_instr_file" "${allowed_tools_instr_file}.tmp" > /dev/null ; then
		warn "Allowed toolset instruction for scope '$scope' is out of sync with the available tools."
		diff -u "$allowed_tools_instr_file" "${allowed_tools_instr_file}.tmp"
		err=1
	    else
		notice "Allowed tools instruction cache for scope '$scope' is up to date"
	    fi
	fi
    fi
    return $err
}

expand_tool_wildcards() {
    local patterns=("$@")
    local all_tools=()
    init_tool_search_dirs
    mapfile -t all_tools < <(jq -r '.[].name' < <(load_all_tool_defs))

    local glob_pattern=$(make_glob_from_var "${patterns[@]}")

    for tool in "${all_tools[@]}"; do
        if [[ -n $glob_pattern && $tool == $glob_pattern ]]; then
	    echo "$tool"
        fi
    done
}

# Handle the maia tool command line
handle_tool_command() {
    # help
    [[ "$1" =~ ^-h|--help$ ]] && tool_usage
    [[ "$2" =~ ^-h|--help$ ]] && tool_usage

    # 1) consume global flags: -h/--help, --scope
    local scope=""
    local scopearg=""
    while [[ $# -gt 0 ]]; do
	case "$1" in
	    -h|--help)
		tool_usage
		return 0
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
    prompt_type="toolset"

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

    local subcmd="${1:-}"
    shift
    
    # compute filename & path
    filename="${prompt_type}.txt"
    filepath="${SCOPE_DIRS[$scope]}/$filename"

    case "$subcmd" in
        list)
	    list_tools "$scope" "$filepath"
            ;;
        restrict)
            # Expand current allowed wildcards to explicit tool names
            mapfile -t allowed_patterns < <(grep -vE '^\s*$' "$filepath" | uniq)
	    mapfile -t expanded_tools < <(expand_tool_wildcards "${allowed_patterns[@]}")
            # Deduplicate
            mapfile -t expanded_tools < <(printf '%s\n' "${expanded_tools[@]}" | sort -u)

            # Remove tools matching restrict patterns
            local filtered_tools=()
            for tool in "${expanded_tools[@]}"; do
                local skip=false
                for pattern in "$@"; do
                    local regex_pattern="^${pattern//\*/.*}$"
                    if [[ "$tool" =~ $regex_pattern ]]; then
                        skip=true
                        break
                    fi
                done
                if ! $skip; then
                    filtered_tools+=("$tool")
                fi
            done

            # Update allowed tools file with filtered explicit list
            printf '%s\n' "${filtered_tools[@]}" > "$filepath"
            refresh_allowed_toolset_files "$scope" "$filepath"
            ;;
	view|"")
	    if [[ "$1" == "--expand" ]] ; then
		mapfile -t allowed_patterns < <(grep -vE '^\s*$' "$filepath" | sort -u)
		expand_tool_wildcards "${allowed_patterns[@]}" | uniq
	    else
		prompt_for_scope "$scope" "$prompt_type"
	    fi
	    ;;
	show)
	    echo "Allowed tools:"
	    echo "--------------"
	    prompt_for_scope "$scope" "$prompt_type"
	    echo "Tool definitions:"
	    echo "-----------------"
	    prompt_for_scope "$scope" "$prompt_type" "json"
	    ;;
	append|enable|allow)
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
	    if [[ "$subcmd" == "enable" || "$subcmd" == "allow" ]] ; then
		subcmd="append"
	    fi
	    handle_text_file_command "$filepath" "$subcmd" "$@"
	    refresh_allowed_toolset_files "$scope" "$filepath"
	    ;;
        edit|read|compose|replace|clear|delete)
	    mkdir -p "${SCOPE_DIRS[$scope]}"
	    handle_text_file_command "$filepath" "$subcmd" "$@"
	    refresh_allowed_toolset_files "$scope" "$filepath"
            ;;
        refresh)
	    refresh_allowed_toolset_files "$scope" "$filepath"
            ;;
        verify)
            verify_tools_def_file "$scope" "$filepath"
            ;;
        *)
            die "Unknown tool command: $subcmd"
            ;;
    esac
}

tool_usage() {
    cat <<EOF
USAGE

  maia tool [--scope <scope>] <command> [<args>...]
     Manage tools
  maia tool --scope
     Show the scope for the current tool definitions

Manage LLM tools/functions.

COMMANDS

  list
      List allowed tools and scope.

  show
      Show allowed tool definitions matching regex.

  edit
      Edit the tool definition in specified scope.

  append|enable|allow <toolname> [<toolname> ...]
      Allowed tool(s) matching regex in current scope.
      Wildcards are allowed in toolname.

  replace [<toolname> ...]
      Replace tool definition (same as clear and append)
      Wildcards are allowed in toolname.

  clear
      Clear all tool definitions in the current scope.

  refresh
      Refresh allowed tools file to sync with discovered .td files.

  verify
      Verify allowed tools are current with discovered .td files.

  delete
      Delete the tool definitions from this scope.

OPTIONS

  --scope <scope>
      Specify scope: session, workspace, home, user, system, extra.

EOF
    exit 0
}
