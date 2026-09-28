#!/usr/bin/env bash
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

# Source common helpers
source "$(dirname "$0")/common.sh"

test_start

# Setup output directory
common_setup_output_dir

# Setup isolated MAIA home environment
setup_maia_home

# Define a helper to run a profile command and check output
run_profile_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_profile_${test_id}" $MAIA profile "$@"
}

run_config_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_config_${test_id}" $MAIA config "$@"
}

run_session_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_session_${test_id}" $MAIA session "$@"
}

run_session_cmd "create_foo_default" create default

run_profile_cmd "create_foo_default" create foo
run_profile_cmd "create_foobar_default" create foo%bar
run_profile_cmd "create_foobargaz_default" create foo%bar%gaz

run_session_cmd "select_foo_1" set --profile foo
run_config_cmd "get_foo_pre_1_t" additional_tool_paths
run_config_cmd "get_foo_pre_1_s" additional_skill_paths

run_config_cmd "set_foo_1" --scope profile additional_tool_paths "test_foo_1"
run_config_cmd "get_foo_1_t" additional_tool_paths
run_config_cmd "get_foo_1_s" additional_skill_paths

run_session_cmd "select_foobar_2" set --profile foo%bar
run_config_cmd "get_foobar_pre_2_t" additional_tool_paths
run_config_cmd "get_foobar_pre_2_s" additional_skill_paths
run_config_cmd "set_foobar_2" --scope profile additional_skill_paths "test_foobar_2"
run_config_cmd "get_foobar_2_t" additional_tool_paths
run_config_cmd "get_foobar_2_s" additional_skill_paths

run_session_cmd "select_foobargaz_3" set --profile foo%bar%gaz
run_config_cmd "get_foobargaz_pre_3_t" additional_tool_paths
run_config_cmd "get_foobargaz_pre_3_s" additional_skill_paths
run_config_cmd "set_foobargaz_3" --scope profile additional_tool_paths "test_foobargaz_3"
run_config_cmd "get_foobargaz_3_t" additional_tool_paths
run_config_cmd "get_foobargaz_3_s" additional_skill_paths

run_session_cmd "select_foobar_2" set --profile foo%bar
run_config_cmd "get_foobar_pre_4_t" additional_tool_paths
run_config_cmd "get_foobar_pre_4_s" additional_skill_paths
run_config_cmd "set_foobar_4" --scope profile additional_skill_paths "test_foobar_4"
run_config_cmd "get_foobar_4_t" additional_tool_paths
run_config_cmd "get_foobar_4_s" additional_skill_paths

run_session_cmd "select_foobargaz" set --profile foo%bar%gaz
run_config_cmd "get_foobargaz_4_t" additional_tool_paths
run_config_cmd "get_foobargaz_4_s" additional_skill_paths

run_session_cmd "select_foo_4" set --profile foo
run_config_cmd "get_foo_4_t" additional_tool_paths
run_config_cmd "get_foo_4_s" additional_skill_paths

run_session_cmd "select_empty" set --profile ""
run_config_cmd "get_e_t" additional_tool_paths
run_config_cmd "get_e_s" additional_skill_paths

run_profile_cmd "delete_foobargaz" delete foo%bar%gaz
run_profile_cmd "delete_boobar" delete foo%bar
run_profile_cmd "delete_foo" delete foo

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
