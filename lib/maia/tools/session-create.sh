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

subsession="${param[session]}"
validate_subsession "$subsession"

actualsession="$(resolve_subsession_name "$subsession")"
# We do not want to unset here, because we want to have workspace and profile copied from the current session
# unset MAIA_SESSION

# Create blank session (do not copy from parent)
if [[ -v param["profile"] ]] ; then
    "$MAIA_BIN" session create "$actualsession" --profile "${param[profile]}" 2>&1 | session_filter
    status=$?
else
    "$MAIA_BIN" session create "$actualsession" 2>&1 | session_filter
    status=$?
fi

if [[ $status != 0 ]] ; then
    exit $status
fi

# Helper function to read config param and run maia command
apply_config_param() {
    local param_name="$1"
    local maia_cmd1="$2"
    local maia_cmd2="$3"
    local value=$(jq -r --arg key "$param_name" '.[$key] // ""' <<< "$_cfg")
    # Git Bash workaround
    value="${value%$'\r'}"
    read -ra patterns <<< "$value"
    if [[ "$maia_cmd2" == allow || "$maia_cmd2" == remember ]] ; then
	parent_allowed=()
	mapfile_from_command parent_allowed $MAIA_BIN "$2" view --expand || true
	glob_pattern=$(make_glob_from_var "${patterns[@]}")
	patterns=()
	for p in "${parent_allowed[@]}" ; do
	    if [[ -n $glob_pattern && $p == $glob_pattern ]]; then
		patterns+=("$p")
	    fi
	done
    fi

    if (( ${#patterns[@]} > 0 )); then
	export MAIA_SESSION="$actualsession"
        "$MAIA_BIN" "$maia_cmd1" "$maia_cmd2" --scope "session" "${patterns[@]}"
	export MAIA_SESSION="$thissession"
    fi
}

thissession="$(resolve_session_name)"
# Make sure to reset, just in case there is defaults from session create
export MAIA_SESSION="$actualsession"
"$MAIA_BIN" tool --scope session clearnonotice
"$MAIA_BIN" skill --scope session clearnonotice
"$MAIA_BIN" skill --scope session forget "*"
export MAIA_SESSION="$thissession"
apply_config_param default_agent_tool_allow tool allow
apply_config_param default_agent_tool_restrict tool restrict
apply_config_param default_agent_skill_allow skill allow
apply_config_param default_agent_skill_restrict skill restrict
apply_config_param default_agent_skill_remember skill remember
apply_config_param default_agent_skill_forget skill forget
