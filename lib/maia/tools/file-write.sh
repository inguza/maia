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

path="$(printf '%b' "${param[path]}")"
validate_path "$path"

session_name="$(resolve_session_name)"
ws_path="$(resolve_workspace_path)"
if [[ -z "$ws_path" ]] ; then
    die "No workspace defined."
fi
ws_changes="${ws_path}/changes/${session_name}"

approval_action=change
if [[ ! -e "$path" ]]; then
    approval_action=create
    # Preserve file-write's existing behavior of creating parent directories.
    mkdir -p "$(dirname -- "$path")"
fi

baseid="${ASSISTANT_BASEID}"
index="$(find_index "$ws_changes" "$baseid")"
id="${baseid}-${index}"
wpath="$(write_file_name "$ws_changes" "$id")"
mkdir -p "$(dirname -- "$wpath")"

contentstr=""
if [[ -v "param[content]" ]] ; then
    printf "%b" "${param[content]}" > "$wpath"
    contentstr="content parameter"
else
    read_file > "$wpath"
    contentstr="standard input"
fi

pfile="$ws_changes/$id-pending.patch"
if [[ ! -e "$path" && ! -s "$wpath" ]]; then
    # A unified diff cannot represent creating a zero-byte file. This marker
    # is handled by change.sh's reversible patch application.
    printf 'MAIA-EMPTY-FILE: %s\n' "$path" > "$pfile"
else
    make_patch "$ws_changes" "$id" "$path"
fi
if [[ -e "$pfile" && ! -s "$pfile" ]] ; then
    rm -f "$pfile" "$wpath"
    clean_meta "$ws_changes" "$baseid" "$index"
    printf '[NOTICE] The requested content from %s already matches %s. No change was created.\n' "$contentstr" "$path"
else
    write_meta "$ws_changes" "$baseid" "$index" "$path"
    if approval_is_allowed "$approval_action" "$path"; then
        if ! "$MAIA_BIN" change apply "$id" >/dev/null 2>&1; then
            printf '[ERROR] The requested file change could not be applied. Check the file state before retrying.\nChange ID: %s\n' "$id" >&2
            exit 1
        fi
        printf '[NOTICE] The requested change has been applied. The change has been logged.\nChange ID: %s\n' "$id"
    else
        printf '[NOTICE] The requested file change requires approval. A pending change is ready for review.\nChange ID: %s\nReview the change and decide whether to apply or skip it.\n' "$id"
        trigger_event "post-change-create" "$id"
    fi
fi
if [[ -e "$path" ]]; then
    $MAIA_BIN file add "$path" > /dev/null 2>&1
fi
# Exit with 0 since otherwise you get an error when there is no match
exit 0
