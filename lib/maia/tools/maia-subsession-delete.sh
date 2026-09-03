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

# "name" is the legacy parameter, "subsession" takes precedence
paramkey="name"
if [[ -v param[subsession] ]] ; then
    paramkey="subsession"
fi
validate_subsession "${param[$paramkey]}"

thissession="$(resolve_session_name)"
actualsession="$(resolve_subsession_name "${param[$paramkey]}")"
unset MAIA_SESSION
"$MAIA_BIN" session delete "$actualsession" 2>&1 | session_filter "$thissession"
