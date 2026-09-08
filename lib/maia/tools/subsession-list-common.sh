#!/bin/bash
# Common implementation for subsession-tool-list and subsession-skill-list
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

# Parse parameters

declare -A param
parseparam

# "name" is the legacy parameter, "subsession" takes precedence
paramkey="name"
if [[ -v param["subsession"] ]] ; then
    paramkey="subsession"
fi
validate_subsession "${param[$paramkey]}"

subsession="${param[$paramkey]}"
actualsession="$(resolve_subsession_name "$subsession")"

# Determine tool or skill command based on script name
export MAIA_SESSION="$actualsession"

# Call maia tool|skill view --expand
"$MAIA_BIN" "$1" view --expand
