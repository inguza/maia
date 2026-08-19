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

wpath="$(write_file_name "$ws_changes" "$id")"
cpath="$(change_file_name "$ws_changes" "$id")"
xpath="$(txt_file_name "$ws_changes" "$id")"

printf '%b' "${param[changes]}" > "${cpath}"
#echo "------------ DEBUG from LLM --------"
#cat "$cpath"
#echo "------------------------------------"

if [[ -e "$cpath" && ! -s "$cpath" ]] ; then
    echo "Patch file empty. Consider it applied."
else
    #echo "$MAIA_CORE_LIB_DIR/change.pl --loglevel WARNING \"$path\" \"$wpath\" \"${cpath}\" ."
    $MAIA_CORE_LIB_DIR/change.pl --loglevel WARNING "$path" "$wpath" "${cpath}" "$xpath" .
    make_patch "$ws_changes" "$id" "$path"
    pfile="$ws_changes/$id-pending.patch"
    if [[ -e "$pfile" && ! -s "$pfile" ]] ; then
	# Empty patch file, removing
	rm -f "$pfile"
    fi
    # Applied cleanly but no change anyway
    if [[ ! -e "$xpath" && ! -e "$pfile" ]] ; then
	write_meta "$ws_changes" "$baseid" "$index" "$path"
        printf '%b' "[ERROR] Changed content identical to the content in $path. No upate made.\n\nFile $path already exists.\n\nChange created for reference:\n$id\n"
    elif [[ -e "$xpath" && ! -e "$pfile" ]] ; then
	rm -f "$wpath"
	write_meta "$ws_changes" "$baseid" "$index" "$path"
        printf '%b' "[ERROR] Permission denied.\n\nFile $path already exists and there were problems applying the change.\n\nChange created for manual resolution:\n$id\n"
    elif [[ -e "$xpath" && -e "$pfile" ]] ; then
	nextindex="$(find_index "$ws_changes" "$baseid")"
	nextid="${baseid}-${nextindex}"
	cnewpath="$(txt_file_name "$ws_changes" "$nextid")"
	xnewpath="$(txt_file_name "$ws_changes" "$nextid")"
	cp "$cpath" "$cnewpath"
	mv "$xpath" "$xnewpath"
	write_meta "$ws_changes" "$baseid" "$index" "$path"
	write_meta "$ws_changes" "$baseid" "$nextindex" "$path"
        printf '%b' "[ERROR] Permission denied.\n\nFile $path already exists. Some of the changes could be applied.\n\nChanges created:\n$id - for the updated content\n$nextid - for the content to apply manually\n"
    else
	write_meta "$ws_changes" "$baseid" "$index" "$path"
	printf '%b' "[ERROR] Permission denied.\n\nFile $path already exists.\n\nChange created:\n$id\n\nThe requested file contents are now represented by this pending change.\n\nThe content of the proposed change is the following:\n"
	echo "\`\`\`patch"
	cat "$pfile"
	echo "\`\`\`"
    fi
fi
