#!/bin/bash
# Remember an instruction
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

scope="session"

if [[ ! -v "param[instructions]" ]]; then
    die "Missing instructions parameter"
fi

declare -a instructions=()

if [[ -n ${param[instructions]:-} ]]; then
    if ! mapfile_from_json instructions "${param[instructions]}" ; then
	die "instructions parse error."
    fi
fi

if [[ "$TOOL_NAME" == "session-instruction-remember" ]] ; then
    set_subsession "${param[session]:-}"
    "$MAIA_BIN" instruction --scope "$scope" remember "${instructions[@]}" | session_filter
else
    "$MAIA_BIN" instruction --scope "$scope" remember "${instructions[@]}"
fi
