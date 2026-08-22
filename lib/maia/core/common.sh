#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

# The built-in fallback system prompt
DEFAULT_SYSTEM_PROMPT_TXT="You are a helpful, knowledgeable assistant.\n"
DEFAULT_FILES_PROMPT_TXT="# Files\n\nWhenever you see a user message starting with 'Files:', treat the fenced blocks as the content of files you may read and modify.\nOnly return files that have new data. When returning a file always indicate the file name by [filename] followed by the fenced content.\n"
DEFAULT_TOOLS_PROMPT_TXT="# Tools\n\n- Multiple tool calls are run in parallel. Tool calls do not receive the results of other tool calls.\n"
DEFAILT_TOOL_INSTR_PROMPT_TXT=""
DEFAULT_TOOLSET_PROMPT_TXT=""
DEFAULT_SKILLS_PROMPT_TXT="# Available skills\n\n"
DEFAULT_SKILLSCONTEXT_PROMPT_TXT="# Skills\n\n"
DEFAULT_SKILLSET_PROMPT_TXT=""
DEFAULT_SKILLSETCONTEXT_PROMPT_TXT=""
# TODO: Get rid of this and instead expand from the default tools prompt
DEFAULT_TOOLSET_PROMPT_JSON="[]"
DEFAULT_SKILLSET_PROMPT_GEN=""
DEFAULT_SKILLSETCONTEXT_PROMPT_GEN=""

# Constants related to tools
TOOLS_DIRNAME="tools"
TOOLSET_DEF_EXT=".td"

# Default configuration values
declare -A DEFAULT_CONFIG=(
    [model]="gpt-4.1-mini"
    [temperature]=0.7
    [max_output_tokens]=32000
    [max_input_tokens]=64000
    [top_p]=1
    [frequency_penalty]=0
    [presence_penalty]=0
    [n]=1
    [stream]=false
    [http_logging]=true
    [term_loglevel]=NOTICE
    [auto_use_at_create]=false
    [auto_use_at_set]=false
    [prune_mode]=reduce
    [prune_when_applied]=true
    [prune_when_skipped]=true
    [additional_tool_paths]=""
    [additional_skill_paths]=""
    [auto_add_new_files_on_apply]=true
    [api_type]="AUTODETECT"
    [api_base_url]="https://api.openai.com"
    [tab_width]=8
    [splice_allowed_files]='\.(?:py|c|cpp|php|js|pl|pm|sh|txt)$'
    [file_handling_mode]=DEFAULT
    [auto_parse]=false
    [default_filter]=''
    [default_session_filesets]='["__SESSION_NAME__"]'
    [default_session_extra_send_filesets]='[]'
    [default_workspace]='__WORKSPACE_USED__'
    [auto_resolve_workspace]=true
    [send_hook]=''
    # Default cost configuration (flat keys with cost_ prefix)
    [cost_input_gpt_4_1]=2
    [cost_output_gpt_4_1]=8
    [cost_input_gpt_4_1_mini]=0.4
    [cost_output_gpt_4_1_mini]=1.6
    [cost_input_gpt_4_1_nano]=0.1
    [cost_output_gpt_4_1_nano]=0.4
    # File handling mode overrides
    [file_handling_mode_mistral_24b]=APPEND
    [file_handling_mode_qwen2_5_14b]=APPEND
)
CONFIG_KEYS=( "${!DEFAULT_CONFIG[@]}" )
readonly CONFIG_KEYS

# Map log levels to numeric priorities
declare -A LOG_PRIORITIES=(
    [DEBUG]=0
    [EXTRA]=1
    [INFO]=2
    [NOTICE]=3
    [WARN]=4
    [ERROR]=5
)

# Scope handling
declare -A SCOPE_DIRS
declare -a SCOPE_ORDER=(session workspace home user system default)
declare -a TOOL_SEARCH_ORDER=(install system user home workspace session extra)
declare -A TOOL_DIRS
declare -a SKILL_SEARCH_ORDER=(install system user home workspace session extra)
declare -A SKILL_DIRS

# Initialize the map of all known scopes to their directories.
# Populates the global associative array SCOPE_DIRS with keys:
#   history, project, home, user, system
# Usage: call init_scope_dirs; then access "${SCOPE_DIRS[$scope]}"
init_scope_dirs() {
    local data_dir="$(resolve_home_dir)"

    local user_dir
    if [[ -n "$MAIA_HOME" ]]; then
	user_dir="$MAIA_HOME/.maia"
    else
	user_dir="$HOME/.maia"
    fi

    SCOPE_DIRS=(
	[session]="$(resolve_session_path)"
	[workspace]="$(resolve_workspace_path)"
	[home]="$data_dir"
	[user]="$user_dir"
	[system]="/etc/maia"
    )
}

# Initialize the map of all known tool paths
# Only call when needed since the jq lookup is a little slow
init_tool_search_dirs() {
    TOOL_DIRS=(
	[session]="${SCOPE_DIRS[session]}/tools"
	[workspace]="${SCOPE_DIRS[workspace]}/tools"
	[home]="${SCOPE_DIRS[home]}/.maia/tools"
	[user]="${SCOPE_DIRS[user]}/tools"
	[system]="${SCOPE_DIRS[system]}/tools"
	[install]="${MAIA_TOOLS_LIB_DIR}"
	[extra]="$(jq -r '.additional_tool_paths' <<<"$_cfg")"
    )
}

init_skill_search_dirs() {
    SKILL_DIRS=(
	[session]="${SCOPE_DIRS[session]}/skills"
	[workspace]="${SCOPE_DIRS[workspace]}/skills:${SCOPE_DIRS[workspace]}/.maia/skills"
	[home]="${SCOPE_DIRS[home]}/.maia/skills"
	[user]="${SCOPE_DIRS[user]}/skills"
	[system]="${SCOPE_DIRS[system]}/skills"
	[install]="${MAIA_SKILLS_LIB_DIR}"
	[extra]="$(jq -r '.additional_skill_paths' <<<"$_cfg")"
    )
}

# Determine terminal log level from config

# Internal: compare two levels
_should_log() {
    local lvl=$1
    local thr=${TERM_LOGLEVEL}
    local lvl_n=${LOG_PRIORITIES[$lvl]}
    local thr_n=${LOG_PRIORITIES[$thr]}
    # show if lvl_n >= thr_n (i.e. severity >= threshold)
    set +e # Necessary workaround for some installations
    (( lvl_n >= thr_n ))
}

# Log helpers
debug()  { _should_log DEBUG  && echo "[DEBUG] $*" >&2; }
info()   { _should_log INFO  && echo "[INFO] $*" >&2; }
extra()  { _should_log EXTRA  && echo "[EXTRA] $*" >&2; }
notice() { _should_log NOTICE && echo "[NOTICE] $*" >&2; }
warn()   { _should_log WARN   && echo "[WARN] $*" >&2; }
error()  { _should_log ERROR  && echo "[ERROR] $*" >&2; }
die()    { set -e ; error "$*"; exit 1; }

# First-letter uppercase check function
is_first_letter_upper() {
    [[ "$1" =~ ^[A-Z@] ]]
}

# Resolve data directory
resolve_home_dir() {
    local home_paths=( $(resolve_home_paths) )
    echo "${home_paths[0]}"
}

# Resolves the DATA_PATHS based on maia_data_search_path
resolve_home_paths() {
    local data_paths=()
    # Check ancestor directories (one level at a time) starting from the current working directory
    local maia_data_search_path=()
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
	# Stop early if we hit $MAIA_HOME or the user's home
	if [[ "$dir" == "$MAIA_HOME" || "$dir" == "$HOME" ]] ; then
	    break
	fi
	maia_data_search_path+=("$dir")
	dir=$(dirname "$dir")
    done

    if [ -n "$MAIA_HOME" ] ; then
	maia_data_search_path+=("$MAIA_HOME")
    fi
    maia_data_search_path+=("$HOME" "/etc")

    # Check for .maia directories in each directory in maia_data_search_path
    # Check each candidate: use “aia” under /etc, otherwise “.maia”
    for dir in "${maia_data_search_path[@]}"; do
	if [[ "$dir" == "/etc" ]]; then
	    candidate="$dir/maia"
	else
	    candidate="$dir/.maia"
	fi

	if [ -d "$candidate" ]; then
	    data_paths+=("$candidate")
	fi
    done

    # If no valid .maia directory is found, fallback to $MAIA_HOME or ~/.maia
    if [ ${#data_paths[@]} -eq 0 ]; then
	if [ -n "$MAIA_HOME" ]; then
	    data_paths+=("$MAIA_HOME/.maia")
	else
	    data_paths+=("$HOME/.maia")
	fi
    fi

    echo "${data_paths[@]}"
}

# determine_implicit_scope — sets $implicit_scope to the first scope
# (in SCOPE_ORDER) whose ${type}.txt exists, or “default” otherwise.
determine_implicit_scope() {
    local type="$1"
    local ext="txt"
    if [[ -n "${2:-}" ]] ; then
	ext="$2"
    fi

    # look in order, but stop before “default” since it has no directory
    for s in "${SCOPE_ORDER[@]}"; do
	[[ "$s" == "default" ]] && break
	if [[ -f "${SCOPE_DIRS[$s]}/${type}.${ext}" ]]; then
	    implicit_scope="$s"
	    return
	fi
    done

    # nothing found on disk use built-in default
    implicit_scope="default"
}

#
# Generic handle functions
#

# $1 = resource key (“workspace” or “session”)
# $2 = optional instance name
handle_x_use() {
    local use_notice="yes"
    if [[ "$1" == "--no-use-notice" ]] ; then
	shift
	use_notice="no"
    fi
    local x=$1;
    shift
    local name="$1"
    if [[ -z "$name" ]] ; then
	name=$(resolve_x_name_raw "$x")
	if [[ -n "$name" ]]; then
	    echo "$name"
	    return
	fi
	if [[ "$x" == "session" ]] ; then
	    echo "default"
	fi
	return
    fi
    if [[ "$x" == "session" && -n "$MAIA_SESSION" ]] ; then
	error "The environment variable MAIA_SESSION is set, cannot use another session. Do 'export MAIA_SESSION=<session> instead."
	return
    fi
    # If they’re already using this, just notice and return
    local current="$(resolve_x_name_raw "$x")"
    if [[ "$name" == "$current" ]]; then
	if [[ "$use_notice" == "yes" ]]; then
            notice "${x^} '$name' is already in use"
	fi
        return
    fi
    if [[ "$x" == "workspace" && "$name" == "__SESSION_WORKSPACE__" ]] ; then
	local session="$(resolve_session_name)"
	local w=$(read_session_workspace_raw "$session")
	if [[ "$w" == "__WORKSPACE_USED__" ]] ; then
	    die "${x^} '$name' gives a circular dependency."
	fi
    fi
    if [[ "$x" == "session" && "$name" == "default" ]] ; then
	ensure_session_exists "$name"
    fi
    local meta="$(resolve_x_meta "$x" "$x" "$name")"
    local base="$(resolve_x_base "$x")"
    [[ -d "$base" ]] || die "${x^} '$name' does not exist"
    [[ -f "$meta" ]] || warn "${x^} '$name' is defunct"
    echo "$name" > "$base/used"
    notice "Now using $x '$name'"
}

# $1 = resource key (“workspace” or “session”)
handle_x_unuse() {
    local x=$1; shift
    if [[ "$x" == "session" && -n "$MAIA_SESSION" ]] ; then
	error "The environment variable MAIA_SESSION is set, cannot unuse the session. Do 'unset MAIA_SESSION' instead."
	return
    fi
    local base="$(resolve_x_base "$x")"
    rm -f "$base/used"
    notice "No longer using any $x."
}

#
# Generic “list” handler for named scopes (workspace, session, etc.)
#
# $1 = resource key (“workspace” or “session”)
handle_x_list() {
    local x="$1"
    local base="$(resolve_x_base "$x")"
    # Determine the active name
    local active="$(resolve_${x}_name)"
    # Loop over subdirectories in base
    for d in "$base"/*/; do
        [[ -d "$d" ]] || continue
        local name="$(basename "$d")"
	local meta_file="$(resolve_x_meta "$x" "$x" "$name")"
	local statstr=""
	if [[ ! -f "$meta_file" ]]; then
	    statstr=" (defunct)"
	fi
        # Mark the active one
        if [[ "$name" == "$active" ]]; then
            printf "* %s%s\n" "$name" "$statstr"
        else
            printf "  %s%s\n" "$name" "$statstr"
        fi
    done
}

#
# Generic “delete” handler for named scopes (workspace, session, etc.)
#
# $1 = resource key (“workspace” or “session”)
# $2 = name of the instance to delete
handle_x_delete() {
    local x="$1";    shift
    local name="$1"; shift
    [[ -n "$name" ]] || die "${x^} name required"
    # Don’t delete the active one
    local active
    active="$(resolve_x_name_raw "$x")"
    [[ "$name" != "$active" ]] || die "Cannot delete the active $x"
    # Remove the directory
    local dir
    dir="$(resolve_x_path "$x" "$name")"
    if [[ ! -d "$dir" ]] ; then
	warn "${x^} '$name' does not exist"
    else
	rm -rf "$dir"
	notice "Deleted $x '$name'"
    fi
}

#
# Generic “edit” handler for named scopes (workspace, session, etc.)
#
# $1 = resource key (“workspace” or “session”)
# $2 = type of file to edit ("workspace", "session", "history")
# $3 = optional instance name
handle_x_edit() {
    local x="$1";    shift
    local type="$1"; shift
    local name="$1"
    # If no name, use the active one
    if [[ -z "$name" ]]; then
        name="$(resolve_"$x"_name)"
    fi
    # Locate the metadata file
    local meta="$(resolve_x_meta "$x" "$type" "$name")"
    [[ -f "$meta" ]] || die "${x^} '$name' does not exist"
    # Launch the editor
    "${EDITOR:-vi}" "$meta"
}

#
# Generic helper functions
#
resolve_x_base() {
    echo "$(resolve_home_dir)/${1}s"
}

# Raw reading only. No tag resolving.
resolve_x_name_raw() {
    local x="$1"
    local base="$(resolve_x_base "$x")"
    local used_file="$base/used"
    if [[ -f "$used_file" ]]; then
	cat "$used_file"
    else
	echo ""
    fi
}

# Full path to a x ($1) directory.
# If you pass a name ($2), it uses that; otherwise it uses the active x.
resolve_x_path() {
    local x="$1"
    local name="$2"
    if [[ -z "$name" ]]; then
	name="$(resolve_${x}_name)"
    fi
    if [[ -n "$name" ]]; then
	echo "$(resolve_${x}_base)/$name"
    fi
}

# Full path to the metadata file ($2.json)
# Accepts an optional name, else uses the active workspace.
resolve_x_meta() {
    local path="$(resolve_${1}_path "$3")"
    if [[ -n "$path" ]] ; then
	echo "$path/$2.json"
    fi
}

#
# Workspace handling
#

resolve_workspace_base() { resolve_x_base "workspace" ; }

read_session_workspace_raw() {
    local sess_name="$1"
    local sess_meta="$(resolve_session_meta "$sess_name")"
    if [[ -e "$sess_meta" ]] ; then
	jq -r '.workspace // empty' < "$sess_meta"
    fi
}

# Enhanced resolve_workspace_name() supporting __SESSION_WORKSPACE__ indirection
resolve_workspace_name() {
    local ws="$1"
    if [[ "$ws" == "__SESSION_WORKSPACE__" ]]; then
        # Indirection to session workspace
        local sess_name="$(resolve_session_name)"
        local ws="$(read_session_workspace_raw "$sess_name")"
	if [[ "$ws" == "__WORKSPACE_USED__" ]]; then
            die "Circular dependency detected: workspace 'used' points to session workspace, which points back to workspace 'used'."
	fi
    fi
    if [[ "$ws" == "" || "$ws" == "__WORKSPACE_USED__" ]]; then
	ws="$(resolve_x_name_raw "workspace")"
    fi
    echo "$ws"
}

# If you pass a name, it uses that; otherwise it uses the active workspace.
resolve_workspace_path() {
    local name="$1"
    if [[ "$name" == "__WORKSPACE_USED__" ]]; then
	name="$(resolve_workspace_name)"
    fi
    resolve_x_path "workspace" "$name"
}
# Accepts an optional name, else uses the active workspace.
resolve_workspace_meta() {
    local name="$1"
    if [[ "$name" == "__WORKSPACE_USED__" ]]; then
	name="$(resolve_workspace_name)"
    fi
    resolve_x_meta "workspace" "workspace" "$name"
}
resolve_changes_path() { echo "$(resolve_workspace_path "$1")/changes"; }
resolve_workspace_root() {
    local ws_name=$1
    local ws_meta="$(resolve_workspace_meta "$ws_name")"
    if [[ -f "$ws_meta" ]] ; then
	echo "$(jq -r .path < "$ws_meta")"
    fi
}
resolve_workspace_filesets() {
    local ws_name=$1
    local ws_meta="$(resolve_workspace_meta "$ws_name")"
    if [[ -f "$ws_meta" ]] ; then
	echo "$(jq -r '.filesets[]' < "$ws_meta")"
    fi
}

# Write workspace.json with the given path and defaults array
# Arguments:
#   $1 = workspace directory (full path to the workspace folder)
#   $2 = filesystem path for the "path" field
#   $3 = JSON array (as a string) for default_session_filesets
write_workspace_meta() {
    local ws_dir="$1"
    local fs_path="$2"
    local filesets_json="$3"
    local meta="$ws_dir/workspace.json"

    jq -n \
       --arg path "$fs_path" \
       --argjson filesets "$filesets_json" \
       '{ path: $path, filesets: $filesets }' \
       > "$meta"
}

resolve_logs_dir() {
    echo "$(resolve_session_path)/logs"
}
resolve_session_base() { resolve_x_base "session" ; }
resolve_session_name() {
    local name="$1"
    if [[ -z "$name" ]] ; then
	if [[ -n "$MAIA_SESSION" ]]; then
	    name="$MAIA_SESSION"
	fi
    fi
    if [[ -z "$name" ]] ; then
	name=$(resolve_x_name_raw "session")
    fi
    if [[ -z "$name" ]] ; then
	echo "default"
    fi
    echo "$name"
}
# If you pass a name, it uses that; otherwise it uses the active session.
resolve_session_path() { resolve_x_path "session" "$1"; }
# Accepts an optional name, else uses the active session.
resolve_session_meta() { resolve_x_meta "session" "session" "$1" ; }
resolve_history_meta() { resolve_x_meta "session" "history" "$1" ; }
# Resolve the workspace name from a session's metadata with indirection support for __WORKSPACE_USED__
resolve_session_workspace() {
    local sess_name="$1"
    local sess_ws_raw="$(read_session_workspace_raw "$sess_name")"
    if [[ -z "$sess_ws_raw" ]]; then
	return
    fi
    if [[ "$sess_ws_raw" == "__WORKSPACE_USED__" ]]; then
        local ws_raw="$(resolve_x_name_raw "workspace")"
        if [[ "$ws_raw" == "__SESSION_WORKSPACE__" ]]; then
            die "Circular dependency detected: session workspace points to workspace 'used' which points back to session workspace."
        fi
        echo "$ws_raw"
    else
        echo "$sess_ws_raw"
    fi
}

#
# Fileset handling
#

resolve_workspace_filesets_json() {
    local meta="$(resolve_workspace_meta "$1")"
    if [[ -e "$meta" ]] ; then
	echo "$(jq -r '.filesets' "$meta")"
    else
	echo "[]"
    fi
}
resolve_workspace_filesets() {
    local meta="$(resolve_workspace_meta "$1")"
    echo "$(jq -r '.filesets[]' "$meta")"
}
resolve_workspace_default_session_filesets() {
    local ws_name="$1"
    local ws_meta="$(resolve_workspace_meta "$ws_name")"
    echo "$(jq -c '.default_session_filesets' < "$ws_meta")"
}
# Echoes a newline-separated list of basenames (no “.fileset”) for all existing .fileset files.
# consume as: mapfile -t EXISTING_FS < <( resolve_all_workspace_filesets "$ws_name" )
resolve_all_workspace_filesets() {
    local ws_name="$(resolve_workspace_name "$1")"
    local ws_dir="$(resolve_workspace_path "$ws_name")"
    if [[ -n "$ws_dir" ]]; then
	if [[ ! -d "$ws_dir" ]] ; then
	    die "Workspace directory $ws_dir does not exist."
	fi
	find "$ws_dir" -maxdepth 1 -type f -name '*.fileset' \
	    | sed -e 's|.*/||;s/\.fileset$//;'
    fi
}

add_file_to_fileset_file() {
    local rel_path="$1"
    local fs="$2"
    local fs_basename=$(basename "$fs" .fileset)
    if [[ -z "$rel_path" ]]; then
	warn "Will not add an empty filename to fileset '$fs_basename'."
	return
    fi
    ensure_file_exists "$fs"
    if grep -Fxq "$rel_path" "$fs"; then
	notice "'$rel_path' already in fileset '$fs_basename'"
    else
	echo "$rel_path" >> "$fs"
	info "'$rel_path' appended to fileset '$fs_basename'"
    fi
}

validate_workspace_exists() {
    local ws_name="$1"
    if [[ "$ws_name" == "__WORKSPACE_USED__" ]]; then
	ws_name="$(resolve_workspace_name)"
    fi
    local ws_dir="$(resolve_workspace_path "$ws_name")"
    if [[ ! -d "$ws_dir" ]]; then
	if [[ -n "$ws_name" ]] ; then
            die "Workspace '$ws_name' does not exist. Create it with 'maia workspace create $ws_name' first."
	else
            warn "No workspace defined. Create a workspace with 'maia workspace create <name>' first and uset or or set <name> to be the default-workspace in the configuration."
	fi
    fi
}

list_to_json() {
    printf '%s\n' $* | jq -R . | jq -s .
}

# validate_subset <candidates_json> <allowed_json> <label>
#   Ensures every element in the first JSON array appears in the second.
#   Exits with an error if any element is missing.
validate_subset() {
    local cand_json="$1"; shift
    local allow_json="$1"; shift
    local label="$1";      shift

    # Load allowed values via jq
    mapfile -t allowed_arr < <(jq -r '.[]' <<<"$allow_json")
    declare -A allowed_map
    for v in "${allowed_arr[@]}"; do
	if [[ -n "$v" ]]; then
            allowed_map["$v"]=1
	fi
    done

    # Load candidate values via jq
    mapfile -t cand_arr < <(jq -r '.[]' <<<"$cand_json")
    for v in "${cand_arr[@]}"; do
        if [[ -z "${allowed_map[$v]}" ]]; then
            die "${label^} '$v' is not permitted. The permitted are: $(printf '%s ' "${allowed_arr[@]}")"
        fi
    done
}

# update_session <name> <bootstrap?> <workspace> <filesets_json>
# - name: session name
# - bootstrap?: "true" to initialize dir+files, "false" to assume exists
# - workspace: workspace name to set
# - filesets_json: JSON array string of filesets
update_session() {
    local name="$1";    shift
    local bootstrap="$1"; shift
    local ws="$1";      shift
    local filesets="$1"; shift
    local extra_send_filesets="$1"; shift || extra_send_filesets="[]"

    local dir="$(resolve_session_path)"

    if [[ "$bootstrap" == "true" ]] ; then
        notice "Bootstrapped session '$name'"
	if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            : > "$dir/history.json"
            : > "$dir/outbox.txt"
	fi
    fi
    local meta="$(resolve_session_meta "$name")"
    jq -n \
       --arg workspace "$ws" \
       --argjson filesets "$filesets" \
       --argjson extra_send_filesets "$extra_send_filesets" \
       '{workspace: $workspace, filesets: $filesets, extra_send_filesets: $extra_send_filesets}' \
       > "$meta"
}

#
# Ensure that the named session exists.
# If no name is passed, uses the active session name.
# If that name is "default" and the session directory is missing, bootstraps it.
# Otherwise, does nothing.
# $1 = optional session name
ensure_session_exists() {
    local name="$(resolve_session_name "$1")"
    local dir="$(resolve_session_path)"
    # If it already exists, nothing to do
    local meta="$(resolve_session_meta "$name")"
    [[ -f "$meta" ]] && return
    # Only auto-create the default session
    if [[ "$name" == "default" ]]; then
	local workspace="$(resolve_session_workspace "$name")"
	if [[ -n "$workspace" ]]; then
	    validate_workspace_exists "$workspace"
	else
	    # Default
	    workspace="__WORKSPACE_USED__"
	fi
	local filesets_json=$(jq -r '.default_session_filesets' <<<"$_cfg")
	update_session "default" "true" "$workspace" "$filesets_json"
    fi
    # For non-default sessions, we now do nothing (no error)
}

ensure_history_exists() {
    local history_file="$1"
    if [[ ! -s "$history_file" ]] \
	   || ! jq -e 'type=="array"' "$history_file" >/dev/null 2>&1; then
	info "Create empty history in $history_file"
	echo '[]' > "$history_file"
    fi
}

ensure_file_exists() {
    local fsf="$1"
    local fs=$(basename $fsf)
    if [ ! -e "$fsf" ] ; then
	info "Auto-create $fs"
	touch "$fsf"
    fi
}

ensure_filesets_exists() {
    local sess_name="$1"
    local workspace="$2"
    local filesets_json="$3"
    local ws_dir="$(resolve_workspace_path "$workspace")"

    # Expand filesets_json to replace markers like __SESSION_NAME__
    local expanded_json=$(expand_filesets "$sess_name" "$workspace" "$filesets_json")
    # Iterate over each fileset in the expanded JSON array and ensure the file exists
    local fs
    for fs in $(jq -r '.[]' <<<"$expanded_json"); do
        ensure_file_exists "$ws_dir/${fs}.fileset"
    done
}

# expand_filesets <workspace_dir> <filesets_json>
# Returns expanded JSON array string with "__WORKSPACE_FILESETS__" replaced by workspace filesets plus any additional entries.
expand_filesets() {
    local sess_name="$(resolve_session_name "$1")"
    local ws_name="$(resolve_workspace_name "$2")"
    local input_json="$3"
    input_json="${input_json/__SESSION_NAME__/${sess_name}}"
    local marker="__WORKSPACE_FILESETS__"

    # Get workspace filesets as JSON array string
    local ws_json="$(resolve_workspace_filesets_json "$ws_name")"

    # Parse the input_json array, separate out marker and others
    # jq filter explanation:
    #  - . as $in | inside input array
    #  - if element == marker, replace by empty array (to remove marker)
    #  - else keep element
    # Then combine with workspace filesets if marker found.
    local contains_marker=$(jq --arg m "$marker" 'index($m) != null' <<<"$input_json")
    if [[ "$contains_marker" == "true" ]]; then
        # Remove marker from input array, keep others
        local filtered=$(jq --arg m "$marker" '[.[] | select(. != $m)]' <<<"$input_json")
        # Combine workspace filesets and filtered others, then uniq
        # jq command: add arrays and get unique values preserving order
        # (jq 1.6 trick for unique by sorting and filtering)
        jq -n --argjson ws "$ws_json" --argjson filtered "$filtered" '
            ($ws + $filtered) | unique
        '
    else
        # No marker, output input as-is
        echo "$input_json"
    fi
}

#
# File content extraction
#
get_session_expanded_filesets() {
    local name="$1"
    local session_meta=$(resolve_session_meta "$name")
    if [[ -e "$session_meta" ]] ; then
	local ws_name=$(resolve_session_workspace "$name")
	local ws_meta="$(resolve_workspace_meta "$ws_name")"
	local sess_fs_raw=$(jq -c '.filesets // []' "$session_meta")
	local ef="$(expand_filesets "$name" "$ws_name" "$sess_fs_raw")"
	echo "$ef"
    fi
}

get_session_expanded_extra_send_filesets() {
    local name="$1"
    local session_meta=$(resolve_session_meta "$name")
    if [[ -e "$session_meta" ]] ; then
	local ws_name=$(resolve_session_workspace "$name")
	local ws_meta="$(resolve_workspace_meta "$ws_name")"
	local e_s_sess_fs_raw=$(jq -c '.extra_send_filesets // []' "$session_meta")
	local esef="$(expand_filesets "$name" "$ws_name" "$e_s_sess_fs_raw")"
	echo "$esef"
    fi
}

apply_default_filter_to_spec() {
    local spec="$1" default_filter="$2"
    # If spec contains | or :, return as is
    if [[ "$spec" == *'|'* || "$spec" == *':'* ]]; then
        echo "$spec"
        return
    fi
    # Load default_filter from config
    if [[ -n "${default_filter}" && "${default_filter}" =~ [^[:space:]] ]]; then
        echo "${spec}|${default_filter}"
    else
        echo "$spec"
    fi
}

session_content_extract() {
    local action="content"
    if [[ "$1" == "--list" ]] ; then
	action="list"
	shift
    fi

    local session="$1"
    shift
    ensure_session_exists "$session"

    # Extract workspace data
    local ws_name=$(resolve_session_workspace "$session")
    # Extract array of fileset names from session meta
    local expanded_filesets=$(get_session_expanded_filesets "$session")
    local filesets=$(jq -r '.[]' <<<"$expanded_filesets")
    local expanded_extra_send_filesets=$(get_session_expanded_extra_send_filesets "$session")
    local extra_send_filesets=$(jq -r '.[]' <<<"$expanded_extra_send_filesets")
    fileset_content_extract "$action" "$ws_name" $filesets $extra_send_filesets
}

# action workspacename fileset1 fileset2...
fileset_content_extract() {
    local action="$1"
    local ws_name="$2"
    shift 2
    local -a filesets=( "$@" )
    local workspace_root="$(resolve_workspace_root "$ws_name")"
    local ws_root=$(resolve_workspace_path "$ws_name")
    local fs
    local -a fs=( "${filesets[@]}" )
    # Loop over filesets in order
    local -a filespecs=()
    local -A seen=()
    local sendset
    local default_filter=$(jq -r '.default_filter // ""' <<<"$_cfg")
    for sendset in "${fs[@]}"; do
	# Resolve path to fileset data file
	local fs_file="$ws_root/${sendset}.fileset"
        [[ -f "$fs_file" ]] || continue
	# Read each line (file spec) in fileset file
	local spec
	while IFS= read -r spec || [[ -n "$spec" ]]; do
	    # Skip empty lines and comments
            [[ -z "$spec" || -n "${seen[$spec]}" || "$spec" =~ ^# ]] && continue
	    if [[ "$action" != "list" ]] ; then
		spec=$(apply_default_filter_to_spec "$spec" "$default_filter")
	    fi
	    filespecs+=("$spec")
	    seen[$spec]=1
	done < "$fs_file"
    done

    case "$action" in
	list)
	    if [[ -z "$workspace_root" ]]; then
		echo "(no workspace root)"
		return
	    fi
	    echo "$workspace_root:"
	    local spec
	    for spec in "${filespecs[@]}" ; do
		printf '    %s\n' "$spec"
	    done
	    ;;
	content)
	    # Output workspace root and file specs
	    if (( ${#filespecs[@]} > 0 )); then
		"$MAIA_CORE_LIB_DIR/extract.pl" --workspace "$workspace_root" "${filespecs[@]}"
	    fi
	    ;;
	*)
	    ;;
    esac
}

#
# Common handling
#

range_defaults() {
    local raw="$1"
    # Some aliasing
    if [[ "$raw" =~ ^([0-9]+)$ ]]; then
        raw="$raw-$raw" 
    fi
    # 1) semantic “last-last” → same as “last”
    if [[ "$raw" == "last-last" ]]; then
        echo "-1:" 
        return
    fi
    # 2) empty or unset → full history
    if [[ -z "$raw" || "$raw" == "all" ]]; then
        echo "0:" 
        return
    fi
    # 3) single “-” or “:” → full history
    if [[ "$raw" == "-" || "$raw" == ":" ]]; then
        echo "0:" 
        return
    fi
    # 4) trailing dash “n-” → open‐ended slice “n:”
    if [[ "$raw" =~ ^([0-9]+)-$ ]]; then
        echo "${BASH_REMATCH[1]}:" 
        return
    fi
    # 5) inclusive “n-m” → exclusive upper bound “n:(m+1)”
    if [[ "$raw" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local s=${BASH_REMATCH[1]} e=${BASH_REMATCH[2]}
        echo "${s}:$(( e + 1 ))" 
        return
    fi
    # 6) keyword “last” → just the last element
    if [[ "$raw" == "last" ]]; then
        echo "-1:" 
        return
    fi
    # 7) “last-n” → the last (n+1) elements: .[-(n+1):]
    if [[ "$raw" =~ ^last-([0-9]+)$ ]]; then
        local n=${BASH_REMATCH[1]}
        echo "-$(( n + 1 )):" 
        return
    fi
    # 8) lone negative “-n” → first (n+1) entries: “0:(n+1)”
    if [[ "$raw" =~ ^-([0-9]+)$ ]]; then
        local n=${BASH_REMATCH[1]}
        echo "0:$(( n + 1 ))" 
        return
    fi
    # 9) anything else—assume it’s valid jq syntax (e.g. “n:m”)
    echo "$raw"
}


# Ensure a command exists
require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
	echo "Error: Required command '$1' not found. Please install it." >&2
	exit 1
    fi
}

# JSON helpers (require jq)
json_get()   { jq -r "$1" "$2"; }
json_pretty() { jq . "$1"; }
json_write() { jq . > "$1"; }

########################################
# CLI Command Recognition
########################################

is_known_command() {
    case "$1" in
	session|workspace|parse|u|user|system|history|h|project|p|fileset|fs|file|f|config|send|s|count|interactive|i|chat|change|c)
	    return 0 ;;
	*)
	    return 1 ;;
    esac
}

edit_file() {
    ${MAIA_EDITOR:-${EDITOR:-vi}} "$1"
}

# Opens the editor for user input and returns the content as a string.
# Returns empty string if the user saved empty content or aborted.
read_text_from_editor() {
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/maia-compose-XXXXXX.txt")
    # Pre-fill with an optional template or empty
    : > "$tmpfile"

    edit_file "$tmpfile"
    if [[ ! -s "$tmpfile" ]]; then
        # Empty file, treat as abort
        rm -f "$tmpfile"
        return 1
    fi
    local content
    content=$(<"$tmpfile")
    rm -f "$tmpfile"
    printf '%s' "$content"
}

# Resolve snippet file path for given scope and snippet name
# Usage: snippet_file_path <scope> <name>
snippet_file_path() {
    local scope="$1"
    local name="$2"
    if [[ -z "${SCOPE_DIRS[$scope]}" ]]; then
	return
    fi
    echo "${SCOPE_DIRS[$scope]}/snippets/${name}.txt"
}

# Find the snippet file and scope for a given snippet name and optional scope
# Usage: find_snippet_scope_and_path <name> [<scope>]
# Returns 0 and echoes "<scope>|<filepath>" if found, else returns 1
find_snippet_scope_and_path() {
    local name="$1"
    local scope="$2"
    if [[ -n "$scope" ]]; then
        local file=$(snippet_file_path "$scope" "$name")
        if [[ -f "$file" ]]; then
            echo "$scope|$file"
            return 0
        else
            return 1
        fi
    fi
    for s in "${SCOPE_ORDER[@]}"; do
	[[ "$s" == "default" ]] && continue
        local file=$(snippet_file_path "$s" "$name")
	if [[ $file && -f "$file" ]]; then
            echo "$s|$file"
            return 0
        fi
    done
    return 1
}

# Exported function to check if a given name corresponds to a snippet,
# and if so, output the snippet content.
# Usage: expand_snippet_name <name>
# Returns 0 and echoes snippet content if found; returns 1 otherwise.
expand_snippet_name() {
    local name="$1"
    local found
    if found=$(find_snippet_scope_and_path "$name"); then
        local file="${found#*|}"
        cat "$file"
        return 0
    fi
    return 1
}

deduplicate_files() {
    local file
    for file in $@ ; do
	if [[ -e "$file" ]] ; then
	    cat "$file" > "${file}.tmp"
	    cat "${file}.tmp" | uniq > "$file"
	    rm -f "${file}.tmp"
	fi
    done
}

# Shared file command handler (used by maia user and maia system)
handle_text_file_command() {
    local file="$1"
    shift || true
    local subcmd="${1:-}"
    case "$subcmd" in
        show)
            shift || true
            [[ -f "$file" ]] && cat "$file"
            ;;
	edit)
	    shift || true
	    edit_file "$file"
	    ;;
        append)
            shift || true
            # Loop over args, detect read or compose or edit
            while [[ $# -gt 0 ]]; do
		case "$1" in
		    +read)
			shift
			cat >> "$file"
			;;
		    +compose)
			shift
			local content
			if content=$(read_text_from_editor); then
			    echo "$content" >> "$file"
			else
			    notice "Compose aborted (empty content)."
			fi
			;;
		    +edit)
			shift
			edit_file "$file"
			;;
                    ++*)
                        echo "${1#+}" >> "$file"
                        shift
                        ;;

                    ==*)
                        echo "${1#=}" >> "$file"
                        shift
                        ;;
		    @*)
			local snippet_name="${1#@}"
			if expanded=$(expand_snippet_name "$snippet_name"); then
			    echo "$expanded" >> "$file"
			else
			    die "Snippet '$snippet_name' not found for explicit @ expansion."
			fi
			;;
		    =*)
			# todo strip = from the file
                        local efile="${1#=}"
			if [[ -f "$efile" ]]; then
                            cat "$efile" >> "$file"
			else
			    warn "File '$efile' do not exist."
			fi
			shift
			;;
		    *)
                        echo "$1" >> "$file"
			shift
			;;
		esac
            done
            ;;
        read)
            shift || true
            cat >> "$file"
            ;;
        compose)
            shift || true
            local content
            if content=$(read_text_from_editor); then
                echo "$content" >> "$file"
            else
                notice "Compose aborted (empty content)."
            fi
            ;;
        replace)
            shift || true
            handle_text_file_command "$file" clear
            handle_text_file_command "$file" append "$@"
            ;;
        clear)
            shift || true
            : > "$file"
            ;;
        delete)
            shift || true
            [[ ! -e "$file" ]] && notice "Nothing to delete"
            rm -f "$file"
            ;;
        *)
            die "Unrecognized command '$subcmd'"
            ;;
    esac
}

prompt_for_scope() {
    local target="$1" type="$2" ext="txt"
    if [[ -n "${3:-}" ]] ; then
	ext=$3
    fi
    local f="$(file_for_scope "$target" "${type}.${ext}")"
    if [[ -n "$f" ]]; then
	cat "$f"
    else
	local T="${type^^}"
	local E="${ext^^}"
	local var="DEFAULT_${T}_PROMPT_${E}"
	printf '%b' "${!var}"
    fi
}

all_command_exec() {
    local pattern="$1"
    local search_path="$2"

    IFS=: read -ra dirs <<< "$search_path"

    for d in "${dirs[@]}"; do
        for path in "$d"/$pattern; do
            [[ -x "$path" ]] || continue
            printf '%s\n' "$path"
        done
    done
}

command_exec_dir() {
    local tool_cmd="$1"
    local tool_search_path="$2"
    # Find full path to executable without relying on PATH for security reasons
    local tool_exec="${tool_cmd%% *}"
    local command_exec_dir=""
    IFS=: read -ra dirs <<< "$tool_search_path"
    for d in "${dirs[@]}"; do
	if [[ -x "$d/$tool_exec" ]]; then
	    command_exec_dir="$d"
	    break
	fi
    done
    printf "%s" "$command_exec_dir"
}

# IMPORTANT! init_tool_search_dirs must be called before a call to this
build_tool_search_path() {
    init_tool_search_dirs
    local paths=()
    local sep=""
    for scope in "${TOOL_SEARCH_ORDER[@]}"; do
	paths+="${sep}${TOOL_DIRS[$scope]}"
	sep=":"
    done
    echo "${paths}"
}

# IMPORTANT! init_skill_search_dirs must be called before a call to this
build_skill_search_path() {
    init_skill_search_dirs
    local paths=()
    local sep=""
    for scope in "${SKILL_SEARCH_ORDER[@]}"; do
	paths+="${sep}${SKILL_DIRS[$scope]}"
	sep=":"
    done
    echo "${paths}"
}

## Config handling
# coerce_to_json: turn a shell string into a JSON literal
coerce_to_json() {
    local raw=$1

    # If it’s literally true/false or a number, emit as-is
    if [[ "$raw" =~ ^(true|false|[0-9]+(\.[0-9]+)?)$ ]]; then
	echo "$raw"
	return
    fi

    # Otherwise quote it as a JSON string
    # Use jq -R to read raw text and output a JSON string
    printf '%s' "$raw" | jq -R .
}

# file_for_scope — starting at $1, walk through SCOPE_ORDER and return
# the first existing <scope>/$2, or an empty string if none found.
file_for_scope() {
    local target="$1"
    local filename="$2"
    local found=false
    for s in "${SCOPE_ORDER[@]}"; do
	# once we hit the target, start checking
	if [[ "$s" == "$target" ]]; then
	    found=true
	fi
	[[ $found != true ]] && continue

	# skip the pseudo-scope “default”
	[[ "$s" == "default" ]] && break

	local f="${SCOPE_DIRS[$s]}/$filename"
	if [[ -f "$f" ]]; then
	    echo "$f"
	    return 0
	fi
    done

    # nothing found
    echo ""
    return 1
}

content_of_file_in_scope() {
    local target="$1"
    local filename="$2"

    # skip the pseudo-scope “default”
    if [[ "$target" != "default" ]] ; then
	local f="${SCOPE_DIRS[$target]}/$filename"
	if [[ -f "$f" ]]; then
	    echo "$f"
	    return
	fi
    fi
    # nothing found
    echo ""
}

load_merged_config() {
    local target_scope="${1:-session}"

    # 1) Seed from DEFAULT_CONFIG
    local jq_args=() jq_fields=()
    for key in "${CONFIG_KEYS[@]}"; do
	local val=${DEFAULT_CONFIG[$key]}
	if [[ "$val" =~ ^(true|false|[0-9]+(\.[0-9]+)?)$ ]]; then
	    jq_args+=(--argjson "$key" "$val")
	else
	    jq_args+=(--arg "$key" "$val")
	fi
	jq_fields+=( "\"$key\": \$$key" )
    done
    local result
    result=$(jq -n "${jq_args[@]}" "{ $(IFS=,; echo "${jq_fields[*]}") }")

    # If the target is the pseudo-scope "default", just return defaults (no disk merges).
    if [[ "$target_scope" == "default" ]]; then
        echo "$result"
        return
    fi

    # 2) Derive merge order by reversing SCOPE_ORDER, skipping "default"
    local scopes=()
    for (( idx=${#SCOPE_ORDER[@]}-1; idx>=0; idx-- )); do
	local s=${SCOPE_ORDER[idx]}
	[[ "$s" == "default" ]] && continue
	scopes+=("$s")
    done

    # 4) Merge each scope up through the target
    for s in "${scopes[@]}"; do
	local cfg=$(content_of_file_in_scope "$s" "config.json")
	if [[ -n "$cfg" ]]; then
	    result=$(jq -s '.[0] * .[1]' <(echo "$result") "$cfg")
	fi
	[[ "$s" == "$target_scope" ]] && break
    done

    # 5) Emit the merged config
    echo "$result"
}

# Helper to convert environment variable MAIA_CURL_EXTRA_HEADERS into curl -H arguments.
# Supports multiple headers separated by newlines.
# Sets the variables in a named variable from first argument
curl_extra_headers() {
    local hdrs="$MAIA_CURL_EXTRA_HEADERS"
    local -n args="$1"
    if [[ -n "$hdrs" ]]; then
        # Split on newlines, add each as -H "header"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                args+=( -H "$line" )
            fi
        done <<< "$hdrs"
    fi
}

make_glob_from_file() {
    local patternfile="$1" result=''
    if [[ ! -e "$patternfile" ]] ; then
	return
    fi
    while IFS= read -r pattern; do
        [[ -z $pattern ]] && continue
        [[ -n $result ]] && result+='|'
        result+="$pattern"
    done < "$patternfile"
    [[ -n $result ]] && printf '@(%s)' "$result"
}

make_glob_from_var() {
    local pattern='' result=''
    for pattern in "$@" ; do
	[[ -z $pattern ]] && continue
        [[ -n $result ]] && result+='|'
        result+="$pattern"
    done
    [[ -n $result ]] && printf '@(%s)' "$result"
}

# Skill execution

skill_execute() {
    local scope="$1"
    local skill="$2"
    local scriptname="$3"
    shift 3
    local status=1

    local skillset_file="${SCOPE_DIRS[$scope]}/skillset.txt"
    local allowed_glob=$(make_glob_from_file "$skillset_file")
    if [[ -n $allowed_glob && $skill == $allowed_glob ]]; then
        local skill_search_path=$(build_skill_search_path)
	local skill_exec_dir="$(command_exec_dir "$skill/$scriptname" "$skill_search_path")"
	if [[ -z "$skill_exec_dir" ]]; then
	    error "Unable to spawn skill script '$scriptname'. Script not found in skill '$skill'."
	    status=2
	else
	    (
		export PATH="$skill_search_path:$PATH"
		cd "$(printf '%q' "$(resolve_workspace_root)")"
		echo '' | "$skill_exec_dir/$skill/$scriptname" "${args[@]}" 2>&1
	    )
	    status=$?
	    if (( status != 0 )); then
		warning "Skill '$skill/$scriptname' failed (status $status)."
	    fi
	fi
    else
	error "Unable to spawn skill script '$scriptname' since skill '$skill' is not allowed."
	status=1
    fi
    return $status
}

### General safe json modification

json_modify() {
    local file="$1"
    shift
    # We always keep the actual file present in case something tries to
    # read it.
    local tmpfile="${file}.tmp.$$"
    if jq "$@" "$file" > "$tmpfile"; then
        mv "$tmpfile" "$file"
        result=0
    else
        rm -f "$tmpfile"
        result=1
    fi
    return $result
}

exclusive_json_modify() {
    local file="$1"
    shift
    acquire_lock "${file}.lock" ""

    local result
    json_modify "$file" "$@"
    result=$?

    release_lock "${file}.lock"
    return $result
}

### Lock handling
session_lock_file() {
    local session_dir=$(resolve_session_path)
    echo "$session_dir/lock"
}

release_lock() {
    rm -f "$1"
}

acquire_lock() {
    local lockfile="$1"
    local lockmessage="${2:-Waiting for lock...}"

    while :; do
	local pid=$$
        local now=$(date +%s)
	# pid and start time of the process is stored so we can use that as identifier of the lock owner
	# the process start time does not change during the lifetime of that pid
	local lockdata="lpid=$pid\nlexpiry=$((now + 3600))"
	if [ -e /proc/version ]; then
	    lockdata="$lockdata\nlstart=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null)"
	fi

        # Atomic acquisition in a subshell
	if ( set -o noclobber; printf '%b\n' "$lockdata" > "$lockfile" ) 2>/dev/null; then
	    return 0
        fi
	# Lock not aquired, see if we can recover or just timeout
        # Lock exists. Read its information.
        if [[ -r "$lockfile" ]]; then
            local lpid="" lexpiry="" lstart="" cstart="-1"
            . "$lockfile" 2>/dev/null
	    if [ -e /proc/version ] ; then
		cstart="$(awk '{print $22}' "/proc/$lpid/stat" 2>/dev/null)"
	    fi

            # Hard expiration: lock is stale regardless of owner.
            if [[ -n "$lexpiry" && "$now" -ge "$lexpiry" ]] ; then
                release_lock "$lockfile"
		continue
	    elif [[ "$cstart" != "-1" && -n "$lstart" &&
			( -z "$cstart" || $cstart -ne $lstart ) ]] ; then
		# If start time of owning pid and start time in lock file is set then check if
		# the owning pid is simply gone (cstart empty) or the start time has changed
		# in such case the process has restarted and can no longer own the lock
                release_lock "$lockfile"
		continue
            fi
        fi

	if [[ -n "$lockmessage" ]] ; then
	   info "$lockmessage"
	fi
	lockmessage=""
	# Try again
        sleep 1
    done
}
###

### Tool handling
pid_starttime() {
    local pid="$1"
    awk '{print $22}' "/proc/$pid/stat"
}

tool_cmd() {
    local tool_tmp_dir="$1"
    local id="$2"
    local tool_exec_dir="$3"
    local tool_cmd="$4"
    local func_args="$5"

    # Do the actual tool call (log to files?)
    local args_file="$tool_tmp_dir/$id.args"
    printf '%s\n' "$func_args" > "$args_file"
    # Make sure to quite since we execute with bash -c
    bash -c "cd $(printf '%q' "$(resolve_workspace_root)"); echo '' | $(printf '%q' "$tool_exec_dir")/$tool_cmd 3<$(printf '%q' "$args_file")" > "$tool_tmp_dir/$id.output" 2>&1
    status=$?
    printf '%s\n' "$status" > "$tool_tmp_dir/$id.finished"
}

tool_fork()
{
    # TODO implement alternative logging depending on who calls it.
    local tool_tmp_dir="$1"
    local id="$2"
    local func_name="$3"
    local func_args="$4"
    local enabled_tools_json="$5"
    local status=0

    local tool_cmd=$(jq -r --arg name "$func_name" '.[] | select(.name == $name) | .command' <<<"$enabled_tools_json")
    if [[ -z "$tool_cmd" ]]; then
	error "Unable to spawn tool for $id (allowed iterations left $allowed_iterations_left): $func_name($func_args). Tool '$func_name' not found."
	status=1
    else
	local tool_search_path=$(build_tool_search_path)

	# Find full path to executable without relying on PATH for security reasons
	local tool_exec="${tool_cmd%% *}"
	local tool_exec_dir="$(command_exec_dir "${tool_cmd}" "$tool_search_path")"
	
	if [[ -z "$tool_exec_dir" ]]; then
	    error "Unable to spawn tool for $id (allowed iterations left $allowed_iterations_left): $func_name($func_args). Executable '$tool_exec' for tool '$func_name' not found in tool search path."
	    status=2
	else
	    (
		export PATH="$tool_search_path:$PATH"
		# Start in a process group
		tool_cmd "$tool_tmp_dir" "$id" "$tool_exec_dir" "$tool_cmd" "$func_args" &
		local jpid=$!
		local starttime="$(pid_starttime "$jpid")"
		jq -n \
		   --argjson pid "$jpid" \
		   --arg starttime "$starttime" \
		   --arg tool "$func_name" \
		   --argjson arguments "$func_args" '{
		     pid: $pid,
		     starttime: $starttime,
		     tool: $tool,
		     arguments: $arguments
		    }' > "$tool_tmp_dir/$id.json"
	    )
	fi
    fi
    return $status
}

### Event handling

hook_execute() {
    local hookcmd="$1"
    local event="$2"
    local extrapath="$3"
    shift 3
    (
	if [[ -n "$extrapath" ]] ; then
	    export PATH="$extrapath:$PATH"
	fi
	"$hookcmd" "$event" "$@"
    )
    local status=$?

    if (( status != 0 )); then
        warning "Hook '$hookcmd' failed for event '$event' (status $status)."
    fi

    # Make sure this call do not terminate the caller
    return 0
}

trigger_event() {
    local event="$1"
    shift
    local -a data=("$@")
    # First look up built in hooks
    for hook in "${MAIA_TOOLS_LIB_DIR}/$event/"*.hook ; do
	[[ -f "$hook" && -x "$hook" ]] || continue
	hook_execute "$hook" "$event" "" "${data[@]}"
    done
    # Then look up tool hooks among the allowed tools
    local tool_search_path="$(build_tool_search_path)"
    local enabled_tools_json="$(prompt_for_scope "session" "toolset" "json")"
    while IFS=$'\t' read -r tool hook_exec; do
	local hook_exec_dir="$(command_exec_dir "${hook_exec}" "$tool_search_path")"
	if [[ -z "$hook_exec_dir" ]]; then
	    warning "Unable to execute '$hook_exec' for event '$event' (not found in tool search path)."
	else
	    hook_execute "$hook_exec_dir/$hook_exec" "$event" "$tool_search_path" "${data[@]}"
	fi
    done < <(
	jq -r --arg event "$event" '
	  .[]
	  | select(.hooks[$event] != null)
	  | [.name, .hooks[$event]]
	  | @tsv
	    ' <<<"$enabled_tools_json")
    # And then skills
    local skill_search_path="$(build_skill_search_path)"
    local skillset_file="$(file_for_scope "session" "skillset.txt")"
    local allowed_glob="$(make_glob_from_file "$skillset_file")"
    if [[ -n $allowed_glob ]] ; then
	while IFS= read -r execpath ; do
	    local skill_path="${execpath%/hooks/$event/*.hook}"
	    local skill="${skill_path##*/}"
	    # check that the skill is allowed
	    if [[ $skill == $allowed_glob ]]; then
		hook_execute "$execpath" "$event" "$skill_search_path" "${data[@]}"
	    fi
	done < <(all_command_exec "*/hooks/${event}/*.hook???" "$skill_search_path")
    fi
}

init_scope_dirs
