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
declare -A param
parseparam

subsession="${param[subsession]:-}"
# TODO check subsession name for unknown characters
if [[ -n "$subsession" ]] ; then
    set_subsession "$subsession"
fi
"$MAIA_BIN" job list
