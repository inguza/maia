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
    local allowed_tools_list_file="$1"
    local allowed_tools_json="[]"
    if [[ -s "$allowed_tools_list_file" ]] ; then
	allowed_tools_json=$(<"$allowed_tools_list_file")
    fi
    jq -r --argjson allowed "$allowed_tools_json" '
        ($allowed | map(.name)) as $allowed_names |
        .[] |
        if (.name | IN($allowed_names[]))
        then "* " + .name + "   (" + .source + ")"
        else "  " + .name + "   (" + .source + ")"
        end
    ' <<< "$all_tools_json"
}
   
# IMPOPRTANT! init_tool_search_dirs
generate_allowed_toolset_def_file() {
    local allowed_tools_list_file="$1"
    local allowed_tools_def_file="$2"
    # Important to call this because it is used by load_all_tool_defs below
    init_tool_search_dirs
    
    local all_tool_defs_json=$(load_all_tool_defs)
    local patterns_json="$(build_list_filter_from_patterns "$allowed_tools_list_file")"

    local default_allowed_effects=$(jq -r '.default_allowed_tool_effects // []' <<<"$_cfg")
    # We match the names against the regexp and then for the matched ones we keep only the last if there are
    # several with the same name.
    # This uses the object index method that overwrites earlier entries
    jq --argjson default_allowed_effects "$default_allowed_effects" \
       --argjson patterns "$patterns_json" \
       -f "$MAIA_CORE_LIB_DIR/generate-allowed-toolset.jq" \
       <<< "$all_tool_defs_json" > "$allowed_tools_def_file"
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
    # Load all tools
    local tmpfile="$(mktemp)"
    load_all_tool_defs > "$tmpfile"
    mapfile_from_command all_tools jq -r '.[].name' < "$tmpfile"
    rm -f "$tmpfile"

    for pattern in "${patterns[@]}"; do
        local tool_pattern="${pattern%%:*}"
        local effect_suffix=""

        if [[ "$pattern" == *:* ]]; then
            effect_suffix=":${pattern#*:}"
        fi

        local glob_pattern=$(make_glob_from_var "$tool_pattern")

        for tool in "${all_tools[@]}"; do
            if [[ -n $glob_pattern && $tool == $glob_pattern ]]; then
                echo "${tool}${effect_suffix}"
            fi
        done
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

    local subcmd="${1:-}"
    shift

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
	if [[ -z "${SCOPE_DIRS[$scope]}" ]]; then
            die "Unknown scope '$scope'. Valid scopes: ${!SCOPE_DIRS[*]}"
	fi
    fi

    # compute filename & path
    local filename="${prompt_type}.txt"
    local filepath="${SCOPE_DIRS[$scope]}/${prompt_type}.txt"
    local filegenpath="${SCOPE_DIRS[$scope]}/${prompt_type}.json"

    case "$subcmd" in
        list)
	    list_tools "$filegenpath"
            ;;
        restrict)
	    # In case there is no file in this scope, copy it over
	    mkdir -p "${SCOPE_DIRS[$scope]}"
	    if [[ ! -f "$filepath" ]]; then
		local msg=$(prompt_for_scope "$implicit_scope" "$prompt_type")
		if [[ -z "$msg" ]] ; then
		    touch "$filepath"
		else
		    echo "$msg" > "$filepath"
		fi
	    fi
            # Expand current allowed wildcards to explicit tool names
            mapfile -t allowed_patterns < "$filepath"
	    mapfile_from_command expanded_tools expand_tool_wildcards "${allowed_patterns[@]}"
            # Deduplicate
	    local tmpfile="$(mktemp)"
	    printf '%s\n' "${expanded_tools[@]}" | sort -u > "$tmpfile"
	    mapfile -t expanded_tools < "$tmpfile"
	    rm -f "$tmpfile"

            # Remove tools matching restrict patterns
            local filtered_tools=()
            for tool in "${expanded_tools[@]}"; do
		local tool_name="${tool%%:*}"
                local skip=false
                for pattern in "$@"; do
                    local regex_pattern="^${pattern//\*/.*}$"
                    if [[ "$tool_name" =~ $regex_pattern ]]; then
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
	discover)
	    init_tool_search_dirs
	    local serverscfg="$(jq -r '.mcp_servers // empty' <<<"$_cfg")"
	    mapfile_from_json servers "$serverscfg"
	    for server in "${servers[@]}" ; do
		local name="${server%%=*}"
		local endpoint="${server#*=}"
		local tooldirs="${TOOL_DIRS[$scope]}"
		local tooldir="${tooldirs%%:*}"
		mkdir -p "${tooldir}"
		local toolfile="${tooldir}/mcp-$name.td"
		printf '%s\n' \
		       '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
		    | mcp_request "discover" "$name" "$endpoint" > "${toolfile}.tmp"
		# Time to parse the output
		# Make sure .mcp_name = .name is before .name is changed
		jq --arg prefix "$name" --arg endpoint "$endpoint" '
		  .result.tools |
		  map(
		    .command = ("mcp.sh " + .name + " " + $prefix + " " + $endpoint) |
		    .name = ($prefix + "-" + .name)
		  )
		  ' < "${toolfile}.tmp" > "$toolfile"
		#rm -f "${toolfile}.tmp"
		notice "Written $toolfile"
	    done
	    ;;
	view|"")
	    if [[ "$1" == "--expand" ]] ; then
		mapfile_from_command allowed_patterns prompt_for_scope "$scope" "$prompt_type"
		expand_tool_wildcards "${allowed_patterns[@]}" | uniq
	    else
		prompt_for_scope "$scope" "$prompt_type"
	    fi
	    ;;
	run)
	    if [[ $# -lt 1 ]]; then
		die "Usage: maia tool run <toolname> [jsonargs]"
	    fi
	    local func_name="$1"
	    local func_args="$2"
	    shift 2
	    local tool_tmp_dir="$(mktemp -d)"
	    local id=manual
	    local enabled_tools_json=$(prompt_for_scope "session" "toolset" "json")
	    local shaid="$(printf '%s' "$func_name($func_args)" | sha256sum | cut -c1-8)"
	    local timestamp=$(date +"%Y%m%dT%H%M%S")
	    export ASSISTANT_BASEID="$timestamp-$shaid"
	    tool_fork \
		"$tool_tmp_dir" \
		"$id" \
		"$func_name" \
		"$func_args" \
		"$enabled_tools_json" \
		" run" > "$tool_tmp_dir/$id.start" 2>&1
	    local status=$?
	    local errormsg=$(<"$tool_tmp_dir/$id.start")
	    if [[ -n "$errormsg" ]] ; then
		echo "$errormsg" >&2
	    else
		wait -n
		local finished="$tool_tmp_dir/manual.finished"
		if [[ -z "$finished" ]]; then
		    die "Tool call malfunction."
		fi
		status="$(<"$tool_tmp_dir/$id.finished")"
		local exitinfo=""
		if (( status != 0 )); then
		    exitinfo="Tool exited with code $status.

"
		fi
		echo "----------------- Tool output $id start ------------------------------------"
		if [[ -n "$exitinfo" ]] ; then
		    echo "$exitinfo"
		fi
		cat "$tool_tmp_dir/$id.output"
		echo "----------------- Tool output $id end --------------------------------------"
	    fi
	    rm -Rf "$tool_tmp_dir"
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
        edit|replace|clear|delete|clearnonotice)
	    mkdir -p "${SCOPE_DIRS[$scope]}"
	    handle_text_file_command "$filepath" "$subcmd" "$@"
	    refresh_allowed_toolset_files "$scope" "$filepath"
            ;;
        refresh)
	    notice "Refreshing scope '$scope'"
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

  run <toolname> [argumentsjsonstring]
      Run a tool directly. The result is not recorded in the conversation history.
      Note that the tool is run detached from stdin and stdout just as when run normally.

  clear
      Clear all tool definitions in the current scope.

  refresh
      Refresh allowed tools file to sync with discovered .td files.

  verify
      Verify allowed tools are current with discovered .td files.

  discover
      Discover additional tools and generate tool definition file(s).

  delete
      Delete the tool definitions from this scope.

OPTIONS

  --scope <scope>
      Specify scope: session, workspace, home, user, system, extra.

EOF
    exit 0
}
