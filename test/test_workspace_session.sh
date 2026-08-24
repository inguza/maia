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

run_workspace_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_workspace_${test_id}" $MAIA workspace "$@"
}

# Test 1: list sessions initially (likely empty or default)
run_session_cmd "list_empty" list

# Test 2: create a new session named 'foo'
run_session_cmd "create_foo_default" create foo
run_session_cmd "list_after_create_foo" list
run_session_cmd "show_after_create_foo" show

# Test 3: create a new session named 'bar'
run_session_cmd "create_bar_use" create bar
export MAIA_SESSION=bar
run_session_cmd "list_after_create_bar" list
run_session_cmd "show_after_create_bar" show

# Test 4: create a new session named 'baz'
run_session_cmd "create_baz_nouse" create baz
run_session_cmd "list_after_create_baz" list
run_session_cmd "show_after_create_baz" show

# Test 5: list sessions again, should show foo, bar, baz
run_session_cmd "list_after_create" list

# Test 6: set session 'baz' with default
run_session_cmd "set_baz_default" set baz
run_session_cmd "list_after_set_baz_default" list
run_session_cmd "show_after_set_baz_default" show baz

# Test 7: set session 'baz'
run_session_cmd "set_baz_use" set baz
export MAIA_SESSION=baz
run_session_cmd "list_after_set_baz_use" list
run_session_cmd "show_after_set_baz_use" show baz

# Test 8 no longer valid

# Test 9: use session 'foo'
export MAIA_SESSION=foo
run_session_cmd "list_after_use_foo" list
run_session_cmd "show_after_use_foo" show

# Test 10: show current session info
run_session_cmd "show_current" show

# Test 11: delete session 'foo' (should succeed if not active)
# Since 'foo' is active, first unuse it
unset MAIA_SESSION
# Now delete 'foo'
run_session_cmd "delete_foo" delete foo
run_session_cmd "list_after_delete_foo" list

# Now test to create sessions with and without resolving
run_workspace_cmd "create_workspace_no_use" create ws

# Now create the session with and without resolving
run_session_cmd "create_session_defaultresolve_noneused" create newsession --workspace ws
run_session_cmd "show_session_defaultresolve_noneused" show newsession

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
