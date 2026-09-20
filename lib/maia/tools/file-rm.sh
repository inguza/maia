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

pathspecs="${param[pathspecs]:-}"
declare -a paths=()
if [[ -n "$pathspecs" ]] ; then
    if ! mapfile_from_json paths "$pathspecs" ; then
	echo "[ERROR] pathspecs parse error."
	exit 3
    fi
else
    echo "[WARNING] No paths specified."
    exit 4
fi
for path in "${paths[@]}" ; do
    validate_path "$path"
done

session_name="$(resolve_session_name)"
ws_path="$(resolve_workspace_path)"
if [[ -z "$ws_path" ]] ; then
    die "No workspace defined."
fi
ws_changes="${ws_path}/changes/${session_name}"

baseid="${ASSISTANT_BASEID}"
index="$(find_index "$ws_changes" "$baseid")"
id="${baseid}-${index}"

wpath="$(action_file_name "$ws_changes" "$id")"
printf '%s' "rm -Rf --" > "$wpath"
printf ' %q' "${paths[@]}" >> "$wpath"
printf '\n' >> "$wpath"
write_meta "$ws_changes" "$baseid" "$index" "${paths[@]}"
printf '%b' "[NOTICE] Direct file modification was not possible.\n\nChange proposal created for manual resolution:\n$id\n"
exit 0
