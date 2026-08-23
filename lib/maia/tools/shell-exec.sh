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

session_name="$(resolve_session_name)"
ws_path="$(resolve_workspace_path)"
ws_changes="${ws_path}/changes/${session_name}"

baseid="${ASSISTANT_BASEID}"
index="$(find_index "$ws_changes" "$baseid")"
id="${baseid}-${index}"

wpath="$(shell_file_name "$ws_changes" "$id")"

commandsstr=""
if [[ -v "param[commands]" ]] ; then
    mkdir -p "$(dirname "$wpath")"
    printf "%b" "${param[commands]}" > "$wpath"
    commandsstr="Commands"
else
    cat > "$wpath"
    commandsstr="Stdin"
fi

write_meta "$ws_changes" "$baseid" "$index" "$path" "shell exec"
printf '%b' "[NOTICE] Direct execution was not possible due to security principles.\n\nExecution proposal created:\n$id\n\nThe requested commands are now represented by this pending execution.\n\n"
# Exit with 0 since otherwise you get an error
exit 0
