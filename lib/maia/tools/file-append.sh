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

if [[ ! -e "$path" ]] ; then
    touch "$path"
fi

contentstr=""
if [[ -v "param[content]" ]] ; then
    printf "%b" "${param[content]}" >> "$path"
    contentstr="Content"
else
    cat >> "$path"
    contentstr="Stdin"
fi

echo "$contentstr appended to $path."
$MAIA_BIN file add "$path" > /dev/null 2>&1 || true
