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

# Test 1: list sessions initially (likely empty or default)
run_session_cmd "list_empty" list

# Test 2: create a new session named 'foo' with default auto_use_at_create=false config (should not auto use)
run_session_cmd "create_foo_default" create foo
run_session_cmd "list_after_create_foo" list
run_session_cmd "show_after_create_foo" show

# Test 3: create a new session named 'bar' with explicit --use (force use)
run_session_cmd "create_bar_use" create bar --use
run_session_cmd "list_after_create_bar" list
run_session_cmd "show_after_create_bar" show

# Test 4: create a new session named 'baz' with explicit --nouse (force no use)
run_session_cmd "create_baz_nouse" create baz --nouse
run_session_cmd "list_after_create_baz" list
run_session_cmd "show_after_create_baz" show baz

# Test 5: list sessions again, should show foo, bar, baz
run_session_cmd "list_after_create" list

# Test 6: set session 'baz' with default auto_use_at_set=false config (should not auto use)
run_session_cmd "set_baz_default" set baz
run_session_cmd "list_after_set_baz_default" list
run_session_cmd "show_after_set_baz_default" show baz

# Test 7: set session 'baz' with explicit --use (force use)
run_session_cmd "set_baz_use" set baz --use
run_session_cmd "list_after_set_baz_use" list
run_session_cmd "show_after_set_baz_use" show baz

# Test 8: set session 'baz' with explicit --nouse (force no use)
run_session_cmd "set_baz_nouse" set baz --nouse
run_session_cmd "list_after_set_baz_nouse" list
run_session_cmd "show_after_set_baz_nouse" show baz

# Test 9: use session 'foo'
run_session_cmd "use_foo" use foo
run_session_cmd "list_after_use_foo" list
run_session_cmd "show_after_use_foo" show

# Test 10: show current session info
run_session_cmd "show_current" show

# Test 11: delete session 'foo' (should succeed if not active)
# Since 'foo' is active, first unuse it
run_session_cmd "unuse" unuse
# Now delete 'foo'
run_session_cmd "delete_foo" delete foo
run_session_cmd "list_after_delete_foo" list

# Defunct handling
mkdir -p .maia/sessions/testdef1
run_session_cmd "testdef1_list" list
run_session_cmd "testdef1_show" show testdef1
run_session_cmd "testdef1_create" create testdef1
run_session_cmd "testdef1_after_create" list
run_session_cmd "testdef1_delete_after_create" delete testdef1
run_session_cmd "testdef1_list_after_delete" list
mkdir .maia/sessions/testdef2
echo test > .maia/sessions/testdef2/outbox.txt
echo "[]" > .maia/sessions/testdef2/history.json
run_session_cmd "testdef2_list" list
run_session_cmd "testdef2_delete" delete testdef2
run_session_cmd "testdef2_list_after_delete" list
mkdir .maia/sessions/testdef3
run_session_cmd "testdef3_list" list
run_session_cmd "testdef3_use" use testdef3
run_session_cmd "testdef3_list_after_use" list
mkdir .maia/sessions/testdef4
run_session_cmd "testdef4_list" list
run_session_cmd "testdef4_set" set testdef4
run_session_cmd "testdef4_show_after_set" show testdef4
run_session_cmd "testdef4_list_after_show" list
rm -Rf .maia/sessions/testdef?

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
