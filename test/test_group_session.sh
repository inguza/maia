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

# Helper to run a session command and check output
run_session_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_session_${test_id}" $MAIA session "$@"
}

run_group_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_group_${test_id}" $MAIA group "$@"
}

# Test 2: create a new session named 'foo'
run_session_cmd "create_foo1" create foo1
run_session_cmd "create_foo2" create foo2
run_session_cmd "create_foo3" create foo3
run_session_cmd "create_bar1" create bar1
run_session_cmd "create_bar2" create bar2
run_session_cmd "create_bar3" create bar3
run_session_cmd "create_gaz1" create gaz1
run_session_cmd "create_gaz2" create gaz2
run_session_cmd "create_gaz3" create gaz3

run_group_cmd "create_a" create a
run_group_cmd "show_a" show a
run_group_cmd "show_a_j" show --json a
run_group_cmd "create_b" create b
run_group_cmd "show_b" show b
run_group_cmd "show_b_j" show --json b
run_group_cmd "create_c" create c
run_group_cmd "show_c" show c
run_group_cmd "show_c_j" show --json c
run_group_cmd "show_a_b" show a b
run_group_cmd "show_a_b_j" show --json a b

run_group_cmd "list" list
run_group_cmd "show" show
run_group_cmd "show_j" show --json

run_group_cmd "add_1_1" add a foo1 foo2
run_group_cmd "add_1_2" add b foo3
run_group_cmd "show_1" show
run_group_cmd "show_j_1" show --json

run_group_cmd "change_1_2" change b foo3 gaz1
run_group_cmd "show_c_j_1" show --json

run_session_cmd "rename_foo1" rename foo1 foo1-renamed
run_group_cmd "show_r_j_1" show --json

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
