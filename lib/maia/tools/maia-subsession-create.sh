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
actualsession="$(resolve_subsession_name "${param[name]}")"
unset MAIA_SESSION
# A subsession is a clone of the current session, but with the following removed:
# - history
# - files
# No extra filesets
"$MAIA_BIN" session create "$actualsession" "$thissession" 2>&1 | session_filter "$thissession" | sed 's/ by copying from.*//;'
export MAIA_SESSION="$actialsession"
"$MAIA_BIN" session set --extra-send-filesets ""
"$MAIA_BIN" history clear
"$MAIA_BIN" file forget "*"
