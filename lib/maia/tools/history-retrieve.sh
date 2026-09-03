#!/bin/bash
# Remember a skill instruction
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

if [[ ! -v "param[ids]" ]]; then
    die "Missing 'ids' parameter"
fi

declare -a ids=()
mapfile -t ids < <(
    jq -r '.[]' <<< "${param[ids]}"
)

history_file="$(resolve_history_meta)"
jq \
    --argjson ids "${param[ids]}" \
    '
    . as $history
    | $ids
    | map(
        . as $prune_id
        | ($prune_id | split("-")) as $parts
        | $history[]
        | select(
            .timestamp == $parts[0]
            and .id == $parts[1]
        )
        | .backup as $backup
        | {
            role: .role,
            content: $backup.content,
            tool_calls: $backup.tool_calls
        }
    )
    ' "$history_file"
