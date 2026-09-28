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

run_tool_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_tool_${test_id}" $MAIA tool "$@"
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
run_tool_cmd "get_foo_pre_1" list

run_tool_cmd "set_foo_1" --scope profile replace "core-pipe"
run_tool_cmd "get_foo_1" list

run_session_cmd "select_foobar_2" set --profile foo%bar
run_tool_cmd "get_foobar_pre_2" list
run_tool_cmd "set_foobar_2" --scope profile replace "core-sequence"
run_tool_cmd "get_foobar_2" list

run_session_cmd "select_foobargaz_3" set --profile foo%bar%gaz
run_tool_cmd "get_foobargaz_pre_3" list
run_tool_cmd "set_foobargaz_3" --scope profile replace "util-find"
run_tool_cmd "get_foobargaz_3" list

run_session_cmd "select_foobar_2" set --profile foo%bar
run_tool_cmd "get_foobar_pre_4" list
run_tool_cmd "set_foobar_4" --scope profile replace "util-grep"
run_tool_cmd "get_foobar_4" list

run_session_cmd "select_foobargaz" set --profile foo%bar%gaz
run_tool_cmd "get_foobargaz_4" list

run_session_cmd "select_foo_4" set --profile foo
run_tool_cmd "get_foo_4" list

run_session_cmd "select_empty" set --profile ""
run_tool_cmd "get_e" list

run_profile_cmd "delete_foobargaz" delete foo%bar%gaz
run_profile_cmd "delete_boobar" delete foo%bar
run_profile_cmd "delete_foo" delete foo

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
