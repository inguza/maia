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

# TODO check host and port for unknown characters

# Use openssl s_client to establish SSL/TLS connection
# Send the data and output the response

# We use timeout to prevent hanging connections; adjust as needed
if [[ -v "param[data]" ]] ; then
    timeout $timeout bash -c "printf '%b' \"${param[data]}\" | openssl s_client -connect \"${param[host]}:${param[port]}\" -quiet"
else
    timeout $timeout bash -c "openssl s_client -connect \"${param[host]}:${param[port]}\" -quiet"
fi
