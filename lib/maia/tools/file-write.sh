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
. "$MAIA_TOOLS_LIB_DIR/file-common.sh"

declare -A param
parseparam

declare -A allowed

session_name="$(resolve_session_name)"
ws_path="$(resolve_workspace_path)"
ws_changes="${ws_path}/changes/${session_name}"

path="$(printf '%b' "${param[path]}")"
validate_path "$path"

baseid="${ASSISTANT_BASEID}"
index="$(find_index "$ws_changes" "$baseid")"
id="${baseid}-${index}"

wpath="$path"
if [[ -e "$path" ]] ; then
    wpath="$(write_file_name "$ws_changes" "$id")"
fi

contentstr=""
if [[ -v "param[content]" ]] ; then
    mkdir -p "$(dirname "$wpath")"
    printf "%b" "${param[content]}" > "$wpath"
    contentstr="Content"
else
    cat > "$wpath"
    contentstr="Stdin"
fi

if [[ "$path" != "$wpath" ]] ; then
    make_patch "$ws_changes" "$id" "$path"
    write_meta "$ws_changes" "$baseid" "$index" "$path"
    pfile="$ws_changes/$id-pending.patch"
    if [[ -e "$pfile" && ! -s "$pfile" ]] ; then
	echo "$contentstr identical to the content in $path. Consider it written."
    else
	printf '%b' "[NOTICE] Direct file modification was not possible.\n\nFile $path already exists.\n\nChange proposal created:\n$id\n\nThe content of the proposed change is the following:\n"
	echo "\`\`\`patch"
	cat "$pfile"
	echo "\`\`\`"
    fi
else
    echo "$contentstr written to $path."
    # If this was a direct write from a tool call, prune arguments in history
    history_file="$(resolve_history_meta)"
    exclusive_json_modify \
	"$history_file" \
	--arg source "$TOOL_CALL_ID" \
	-f "$MAIA_HOOKS_LIB_DIR/prune-tool-call-args.jq"
fi
$MAIA_BIN file add "$path" > /dev/null 2>&1
# Exit with 0 since otherwise you get an error when there is no match
exit 0
