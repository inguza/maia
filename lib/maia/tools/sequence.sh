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

enabled_tools_json=$(prompt_for_scope "session" "toolset" "json")
tool_search_path=$(build_tool_search_path)
export PATH="$tool_search_path:$PATH"

tool_tmp_dir="$(mktemp -d)"

sequence="$(printf '%b' "${param[sequence]}")"
i=1

debug "Running sequence from workspace root"
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
	die "Executable '$func_name' does not have a defined tool command."
    fi

    # Find full path to executable without relying on PATH for security reasons
    tool_exec="${tool_cmd%% *}"
    tool_exec_dir="$(command_exec_dir "${tool_cmd}" "$tool_search_path")"
	
    if [[ -z "$tool_exec_dir" ]]; then
	rm -rf "$tool_tmp_dir"
	die "Executable '$tool_exec' for tool '$func_name' not found in tool search path."
    else
	# TODO Call it
	args_file="$tool_tmp_dir/$i.args"
	printf '%s\n' "$func_args" > "$args_file"
	notice "Tool call $i in sequence: $func_name($func_args)"
	echo "----------------- Tool output $i start ------------------------------------"
	bash -c "cd $(printf '%q' "$(resolve_workspace_root)"); echo '' | $(printf '%q' "$tool_exec_dir")/$tool_cmd 3<$(printf '%q' "$args_file")" 2>&1
	echo
	echo "----------------- Tool output $i end --------------------------------------"
    fi
    ((i++))
done < <(jq -c '.[]' <<< "$sequence")

rm -rf "${tool_tmp_dir}"

exit 0
