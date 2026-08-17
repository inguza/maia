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

# Define a helper to run a workspace command and check output
run_workspace_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_workspace_${test_id}" $MAIA workspace "$@"
}

# Test 1: list workspaces in a fresh home (should be empty or default)
run_workspace_cmd "list_empty" list

# Test 2: create a new workspace named 'foo' with default auto_use_at_create=false config (should not auto use)
run_workspace_cmd "create_foo_default" create foo
run_workspace_cmd "list_after_create_foo" list
run_workspace_cmd "show_after_create_foo" show foo

# Test 3: create a new workspace named 'bar' with explicit --use (force use)
run_workspace_cmd "create_bar_use" create bar --use
run_workspace_cmd "list_after_create_bar" list
run_workspace_cmd "show_after_create_bar" show

# Test 4: create a new workspace named 'baz' with explicit --nouse (force no use)
run_workspace_cmd "create_baz_nouse" create baz --nouse
run_workspace_cmd "list_after_create_baz" list
run_workspace_cmd "show_after_create_baz" show baz
run_workspace_cmd "show_after_create_baz_curr" show

# Test 5: list workspaces again, should show foo, bar, baz
run_workspace_cmd "list_after_create" list

# Test 6: set workspace 'baz' with default auto_use_at_set=true config (should auto use)
run_workspace_cmd "set_baz_default" set baz
run_workspace_cmd "list_after_set_baz_default" list
run_workspace_cmd "show_after_set_baz_default" show baz

# Test 7: set workspace 'baz' with explicit --use (force use)
run_workspace_cmd "set_baz_use" set baz --use
run_workspace_cmd "list_after_set_baz_use" list
run_workspace_cmd "show_after_set_baz_use" show baz

# Test 8: set workspace 'baz' with explicit --nouse (force no use)
run_workspace_cmd "set_baz_nouse" set baz --nouse
run_workspace_cmd "list_after_set_baz_nouse" list
run_workspace_cmd "show_after_set_baz_nouse" show baz

# Test 9: use workspace 'foo'
run_workspace_cmd "use_foo" use foo
run_workspace_cmd "list_after_use_foo" list
run_workspace_cmd "show_after_use_foo" show

# Test 10: show current workspace info
run_workspace_cmd "show_current" show

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
