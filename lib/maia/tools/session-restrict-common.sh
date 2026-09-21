#!/bin/bash
# Common implementation for session-tool-restrict and session-skill-restrict
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
set -eo pipefail

. "$MAIA_TOOLS_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/session-common.sh"

declare -A param
parseparam

session="${param[session]}"
validate_subsession "$session"

actualsession="$(resolve_subsession_name "$session")"

# Determine tool or skill command based on script name
export MAIA_SESSION="$actualsession"

restrictions=()
if [[ -n ${param[restrictions]:-} ]]; then
    if output=$(jq -r '.[]' <<< "${param[restrictions]}" 2> /dev/null ) ; then
        if [[ -n "$output" ]]; then
            mapfile -t restrictions <<< "$output"
        fi
    else
        printf '[ERROR] Argument parsing error\n' >&2
        exit 1
    fi
fi

# Call maia tool|skill view --expand
"$MAIA_BIN" "$1" restrict "${restrictions[@]}"
