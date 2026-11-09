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
if [[ -z "$ws_path" ]] ; then
    die "No workspace defined."
fi
ws_changes="${ws_path}/changes/${session_name}"

path="$(printf '%b' "${param[path]}")"
validate_path "$path"

baseid="${ASSISTANT_BASEID}"
index="$(find_index "$ws_changes" "$baseid")"
id="${baseid}-${index}"

if [[ ! -e "$path" ]] ; then
    echo "File '$path' does not exist." >&2
    exit 1
fi

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
	rm -f "$wpath"
	rm -f "$cpath"
	clean_meta "$ws_changes" "$baseid" "$index"
        printf '%b' "[NOTICE] File already contains the requested content. No change made.\n"
    elif [[ -e "$xpath" && ! -e "$pfile" ]] ; then
	rm -f "$wpath"
	write_meta "$ws_changes" "$baseid" "$index" "$path"
        if approval_is_allowed change "$path"; then
            printf '%b' "[NOTICE] The requested text could not be matched exactly, so no changes were applied and the file is unchanged.\nChange ID: $id\nResolve the change manually before applying or skipping it.\n"
        else
            printf '%b' "[NOTICE] The requested file change requires approval. The requested text could not be matched exactly, so no changes were applied and the file is unchanged.\nChange ID: $id\nResolve the change manually before applying or skipping it.\n"
        fi
	trigger_event "post-change-create" "${baseid}-${index}"
    elif [[ -e "$xpath" && -e "$pfile" ]] ; then
	nextindex="$(find_index "$ws_changes" "$baseid")"
	nextid="${baseid}-${nextindex}"
	cnewpath="$(txt_file_name "$ws_changes" "$nextid")"
	xnewpath="$(txt_file_name "$ws_changes" "$nextid")"
	cp "$cpath" "$cnewpath"
	mv "$xpath" "$xnewpath"
	write_meta "$ws_changes" "$baseid" "$index" "$path"
	write_meta "$ws_changes" "$baseid" "$nextindex" "$path"
        if approval_is_allowed change "$path"; then
            printf '%b' "[NOTICE] Only some requested text could be matched. No part was applied and the file is unchanged.\nChange ID: $id (matched patch portion)\nChange ID: $nextid (manual-resolution portion)\nResolve both portions manually before applying or skipping them.\n"
        else
            printf '%b' "[NOTICE] The requested file change requires approval. Only some requested text could be matched; no part was applied and the file is unchanged.\nChange ID: $id (matched patch portion)\nChange ID: $nextid (manual-resolution portion)\nReview both portions and resolve the unmatched text before applying or skipping them.\n\nThe content of the matched patch portion is the following:"
        fi
	echo "\`\`\`patch"
	read_file_by_line "$pfile"
	echo "\`\`\`"
	trigger_event "post-change-create" "${baseid}-${index}"
	trigger_event "post-change-create" "${baseid}-${nextindex}"
    else
	write_meta "$ws_changes" "$baseid" "$index" "$path"
        if approval_is_allowed change "$path"; then
            if "$MAIA_BIN" change apply "$id" >/dev/null 2>&1; then
                printf '[NOTICE] The requested change has been applied and the file has been updated.\nChange ID: %s\n' "$id"
                exit 0
            fi
            printf '[ERROR] The approved change could not be applied. The file may be unchanged. Change ID: %s\n' "$id" >&2
            exit 1
        fi
	printf '%b' "[NOTICE] The requested file change requires approval. It has not been applied and the file is unchanged.\nChange ID: $id\nReview the change and decide whether to apply or skip it.\n\nThe content of the proposed change is the following:\n"
	echo "\`\`\`patch"
	read_file_by_line "$pfile"
	echo "\`\`\`"
	trigger_event "post-change-create" "${baseid}-${index}"
    fi
fi
