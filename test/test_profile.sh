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

run_profile_cmd "help" --help

# Test 1: list profiles in a fresh home (should be empty or default)
run_profile_cmd "list_empty" list
run_profile_cmd "query_empty"

# Test 2: create a new profile named 'foo'
run_profile_cmd "create_foo_default" create foo
run_profile_cmd "list_after_create_foo" list

# Test 3: create a new profile named 'bar'
run_profile_cmd "create_bar_use" create bar
run_profile_cmd "list_after_create_bar" list

# Test 4: create a new profile named 'baz'
run_profile_cmd "create_baz_nouse" create baz
run_profile_cmd "list_after_create_baz" list

# Test 5: list profiles again, should show foo, bar, baz
run_profile_cmd "list_after_create" list

# Test 6: delete profile
run_profile_cmd "delete_baz_nouse" delete baz
run_profile_cmd "list_after_delete_baz" list

# Different scopes
run_profile_cmd "create_h1" --scope home create h_1 "Test profile for home scope level 1"
run_profile_cmd "create_h1_2" --scope home create h_1%h_2 "Test profile for home scope level 2"
run_profile_cmd "create_h1_2_x" --scope home create h_1%h_2%xx "Test profile for home scope level 3"
run_profile_cmd "create_h1_3" --scope home create h_1%h_3
run_profile_cmd "create_h2" --scope home create h_2 "Test profile 2 for home scope level 1"
run_profile_cmd "create_h2_4" --scope home create h_2%h_4
run_profile_cmd "create_h2_4_x" --scope home create h_2%h_4%xx

run_profile_cmd "create_s1" create s_1
run_profile_cmd "create_s1_2" create s_1%s_2
run_profile_cmd "create_s1_2_x" create s_1%s_2%xx
run_profile_cmd "create_s1_2_y" create s_1%s_2%yy
run_profile_cmd "create_s1_3" create s_1%s_3
run_profile_cmd "create_s2" create s_2

run_profile_cmd "list_after_create_various_scopes" list

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
