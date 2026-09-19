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

run_profile_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_profile_${test_id}" $MAIA profile "$@"
}

run_workspace_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_workspace_${test_id}" $MAIA workspace "$@"
}

# Test 1: list sessions initially (likely empty or default)
run_session_cmd "list_empty" list

# Test 2: create a new session named 'foo'
run_session_cmd "create_foo_default" create foo --profile notxisting

# Test 2: create a new session named 'foo'
run_profile_cmd "create_foo_default" create testprofile

run_session_cmd "create_foo_testprofile" create foo --profile testprofile
run_session_cmd "show_foo_testprofile" show foo
run_session_cmd "set_foo_empty" set foo --profile ""
run_session_cmd "show_foo_empty" show foo

run_session_cmd "create_bar_default" create bar
run_session_cmd "show_bar_default" show bar
run_session_cmd "set_bar_testprofile" set bar --profile testprofile
run_session_cmd "show_bar_testprofile" show bar


# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
