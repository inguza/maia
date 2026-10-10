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

declare -a paths=()
parsepathspecs pathspecs

if ((${#paths[@]} == 0)); then
    echo "[WARNING] No paths specified."
    exit 4
fi
destination="${param[destination]:-}"
if [[ -z "$destination" ]] ; then
    echo "[WARNING] No destination specified."
    exit 5
fi
validate_path "$destination"

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
printf '%s' "mv -f --" > "$wpath"
printf ' %q' "${paths[@]}" "$destination" >> "$wpath"
printf '\n' >> "$wpath"
printf '%s' "maia file forget" >> "$wpath"
printf ' %q' "${paths[@]}" >> "$wpath"
printf '\n' >> "$wpath"
# Now to the complicated part, to determine what remembered files are changed
mapfile_from_command file_context maia file --raw list
move_into_destination=false
if [[ -d "$destination" || ${#paths[@]} -gt 1 ]]; then
    move_into_destination=true
fi
declare -a remember=()
for source in "${paths[@]}"; do
    source="${source%/}"
    for remembered in "${file_context[@]}"; do
	rfile="${remembered%%[|:]*}"
	rsuffix="${remembered:${#rfile}}"
	if [[ -d "$source" ]] ; then
	    [[ "$rfile" == "$source/"* ]] || continue
	    rfile="${rfile#"$source"}"
	else
	    [[ "$rfile" == "$source" ]] || continue
	    rfile=""
	fi
	if [[ "$move_into_destination" == true ]]; then
            remember+=("${destination%/}/$(basename "$source")${rfile}$rsuffix")
	else
	    remember+=("$destination$rsuffix")
	fi
    done
done

printf '%s' "maia file remember" >> "$wpath"
printf ' %q' "${remember[@]}" >> "$wpath"
printf '\n' >> "$wpath"
# * join to one entry
write_meta "$ws_changes" "$baseid" "$index" "${paths[*]}"
printf '%b' "[NOTICE] Direct file modification was not possible.\n\nChange proposal created for manual resolution:\n$id\n"
exit 0
