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
. "$MAIA_TOOLS_LIB_DIR/session-common.sh"
declare -A param
parseparam

thissession="$(resolve_session_name)"
subsession="${param[session]}"
# TODO check session that it does not contain any unknown characters

set_subsession "$subsession"
if [[ -v "param[content]" ]] ; then
    printf "%b" "${param[content]}" | "$MAIA_BIN" send read 2>&1 | session_filter "$thissession"
else
    "$MAIA_BIN" send read 2>&1 | session_filter "$thissession"
fi
