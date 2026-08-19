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

startline="${param[startline]:-}"
stopline="${param[stopline]:-}"
filepattern="$(printf '%b' "${param[filepattern]}")"
if [[ -n "$startline" || -n "$stopline" ]] ; then
    filepattern="$filepattern:$startline-$stopline"
fi
thissession="$(resolve_session_name)"
subsession="${param[session]:-}"
# TODO check session name for unknown characters
if [[ -n "$subsession" ]] ; then
    set_subsession "$subsession"
fi
"$MAIA_BIN" file remember "$filepattern" 2>&1 | session_filter "$thissession"
