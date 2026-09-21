#!/bin/bash
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

subsession="${param[subsession]}"
set_subsession "$subsession"
if [[ -v "param[content]" ]] ; then
    printf "%b" "${param[content]}" | "$MAIA_BIN" send --output-mode "final" +read 2>&1 | session_filter
else
    "$MAIA_BIN" send --output-mode "final" +read 2>&1 | session_filter
fi

exit 0
