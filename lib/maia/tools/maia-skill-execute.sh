#!/bin/bash
# Execute a skill script with optional arguments.
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

declare -A param
parseparam

skill="${param[skill]}"
script="${param[script]}"
scope="session"

if [[ -z "$skill" || -z "$script" ]]; then
    die "Missing skill or script parameter"
fi
if [[ "$skill" !~ ^[0-9a-zA-Z_]+$ ]] ; then
    die "Invalid characters in skill '$skill'."
fi
validate_path "$script"

declare -a arguments=()
parsearguments

skill_execute "$scope" "$skill" "$script" "${arguments[@]}"
