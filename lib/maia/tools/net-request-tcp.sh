#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam
timeout=30
ttmp="${param[timeout]:-}"
if [[ -n "$ttmp" && "$ttmp" =~ ^[0-9]+$ ]] ; then
    timeout="$ttmp"
fi

if [[ -v "param[data]" ]] ; then
    timeout $timeout bash -c "printf '%b' \"${param[data]}\" | netcat \"${param[host]}\" \"${param[port]}\""
else
    timeout $timeout bash -c "netcat \"${param[host]}\" \"${param[port]}\""
fi
