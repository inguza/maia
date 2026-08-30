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
# We do not want to unset here, because we want to have workspace copied from the current session
# unset MAIA_SESSION

echo "DEBUG: $actualsession"

# Create blank subsession (do not copy from parent)
"$MAIA_BIN" session create "$actualsession" 2>&1 | session_filter "$thissession"

export MAIA_SESSION="$actualsession"

# Read config parameters for default subsession setup
_cfg=$(load_merged_config session)

# Helper function to read config param and run maia command
apply_config_param() {
    local param_name="$1"
    local maia_cmd1="$2"
    local maia_cmd2="$3"
    local value=$(jq -r --arg key "$param_name" '.[$key] // ""' <<< "$_cfg")
    read -ra patterns <<< "$value"
    if (( ${#patterns[@]} > 0 )); then
        "$MAIA_BIN" "$maia_cmd1" "$maia_cmd2" --scope "session" "${patterns[@]}"
    fi
}

apply_config_param default_subsession_tool_allow tool allow
apply_config_param default_subsession_tool_restrict tool restrict
apply_config_param default_subsession_skill_allow skill allow
apply_config_param default_subsession_skill_restrict skill restrict
apply_config_param default_subsession_skill_remember skill remember
apply_config_param default_subsession_skill_forget skill forget
