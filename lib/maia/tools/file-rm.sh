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
printf '%s' "maia file forget" >> "$wpath"
printf ' %q' "${paths[@]}" >> "$wpath"
printf '\n' >> "$wpath"
write_meta "$ws_changes" "$baseid" "$index" "${paths[*]}"

if approval_is_allowed delete "${paths[@]}"; then
    "$MAIA_BIN" change run "$id" >/dev/null 2>&1 || true
    status_file="$ws_changes/${id}-finished.exit_status"
    if [[ -f "$status_file" && "$(read_file "$status_file")" == "0" ]]; then
        printf '[NOTICE] The requested change has been applied. The change has been logged.\nChange ID: %s\n' "$id"
        exit 0
    fi
    printf '[ERROR] Pre-approved deletion failed. Change ID: %s\n' "$id" >&2
    exit 1
fi

printf '%b' "[NOTICE] The requested file change requires approval. A pending change is ready for review.\nChange ID: $id\nReview the change and decide whether to 'do' it or skip it."
exit 0
