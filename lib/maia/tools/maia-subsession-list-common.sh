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

# Parse parameters

declare -A param
parseparam

subsession="${param[name]}"

if [[ -z "$subsession" ]]; then
    die "Missing required parameter 'name' or 'subsession'"
fi

# Validate subsession name
if ! [[ "$subsession" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    die "Invalid subsession name '$subsession'. Allowed characters are letters, numbers, underscore and hyphen."
fi

if [[ -z "$subsession" ]] ; then
    die "Invalid subsession name '$subsession'. Must not be empty."
fi

actualsession="$(resolve_subsession_name "$subsession")"

# Determine tool or skill command based on script name
export MAIA_SESSION="$actualsession"

# Call maia tool|skill view --expand
"$MAIA_BIN" "$1" view --expand
