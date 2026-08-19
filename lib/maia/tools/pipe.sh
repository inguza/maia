#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam

enabled_tools_json=$(tools_for_scope "session" "toolset")
tool_search_path=$(build_tool_search_path)
export PATH="$tool_search_path:$PATH"

tool_tmp_dir="$(mktemp -d)"

pipeline="$(printf '%b' "${param[pipeline]}")"
i=1
pipeline_cmd="echo ''"

while IFS= read -r tool_call; do
    func_name=""
    func_name=$(jq -r '.name' <<<"$tool_call")
    if [[ "$func_name" == "null" ]] ; then
	func_name=""
    fi
    # Strip the functions. namespace
    func_name="${func_name#functions.}"
    func_args=""
    if [[ -n "$func_name" ]] ; then
	func_args=$(jq -r '.arguments' <<<"$tool_call")
    fi
    tool_cmd=$(jq -r --arg name "$func_name" '.[] | select(.name == $name) | .command' <<<"$enabled_tools_json")
    if [[ -z "$tool_cmd" ]] ; then
	rm -rf "$tool_tmp_dir"
	die "Tool '$func_name' does not have a defined tool command."
    fi

    # Find full path to executable without relying on PATH for security reasons
    tool_exec="${tool_cmd%% *}"
    tool_exec_dir="$(tool_exec_dir "${tool_exec}" "$tool_search_path")"
	
    if [[ -z "$tool_exec_dir" ]]; then
	rm -rf "$tool_tmp_dir"
	die "Executable '$tool_exec' for tool '$func_name' not found in tool search path."
    else
	# Build the pipe
	args_file="$tool_tmp_dir/$i.args"
	printf '%s\n' "$func_args" > "$args_file"
	debug "Command $i in pipeline: $func_name($func_args)"
	# Make sure to quite since we execute with bash -c later
	pipeline_cmd+=" | $(printf '%q' "$tool_exec_dir")/$tool_cmd 3<$(printf '%q' "$args_file")"
    fi
    ((i++))
done < <(jq -c '.[]' <<< "$pipeline")

# Make sure to quite since we execute with bash -c
debug "Running pipelne as '$pipeline_cmd' from workspace root"
bash -c "cd $(printf '%q' "$(resolve_workspace_root)"); $pipeline_cmd" || true

rm -rf "${tool_tmp_dir}"

# Exit with 0 since otherwise you get an error when there is no match
exit 0
