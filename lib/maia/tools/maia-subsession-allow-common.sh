#!/bin/bash
# Common implementation for subsession-tool-restrict and subsession-skill-restrict
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

allow=()
if [[ -n ${param[allow]:-} ]]; then
    if output=$(jq -r '.[]' <<< "${param[allow]}" 2> /dev/null ) ; then
        if [[ -n "$output" ]]; then
            mapfile -t allow <<< "$output"
        fi
    else
        printf '[ERROR] Argument parsing error\n' >&2
        exit 1
    fi
fi

parent_allowed=()
mapfile -t parent_allowed < <($MAIA_BIN "$1" view --expand)

# Determine tool or skill command based on script name
export MAIA_SESSION="$actualsession"

# Filter requested tools to those allowed in parent
glob_pattern=$(make_glob_from_var "${allow[@]}")
allowed=()
for p in "${parent_allowed[@]}" ; do
    if [[ -n $glob_pattern && $p == $glob_pattern ]]; then
	allowed+=("$p")
    fi
done

# Call maia tool|skill view --expand
"$MAIA_BIN" "$1" --scope session allow "${allowed[@]}"
