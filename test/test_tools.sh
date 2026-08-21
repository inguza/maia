#!/usr/bin/env bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
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
run_tools_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_tools_${test_id}" $MAIA tools "$@"
}

# Test 0: The help
run_tools_cmd "help" --help

run_tools_cmd "list" list
run_tools_cmd "show_empty" show
run_tools_cmd "scope_empty" --scope
run_tools_cmd "refresh_empty" refresh
run_tools_cmd "verify_empty" verify

run_tools_cmd "append" append "core-pipe"
run_tools_cmd "list_after_append_pipe" list
run_tools_cmd "show_after_append_pipe" show
run_tools_cmd "scope_after_append_pipe" --scope
run_tools_cmd "refresh_after_append_pipe" refresh
run_tools_cmd "verify_after_append_pipe" verify

run_tools_cmd "enable" enable "core-sequence"
run_tools_cmd "list_after_enable_seq" list
run_tools_cmd "show_after_enable_seq" show
run_tools_cmd "scope_after_enable_seq" --scope
run_tools_cmd "refresh_after_enable_seq" refresh
run_tools_cmd "verify_after_enable_seq" verify

run_tools_cmd "allow" allow "core-print"
run_tools_cmd "list_after_allow_print" list
run_tools_cmd "show_after_allow_print" show
run_tools_cmd "scope_after_allow_print" --scope
run_tools_cmd "refresh_after_allow_print" refresh
run_tools_cmd "verify_after_allow_print" verify

run_tools_cmd "replace" replace "net-request*"
run_tools_cmd "list_after_replace_mul" list
run_tools_cmd "show_after_replace_mul" show
run_tools_cmd "scope_after_replace_mul" --scope
run_tools_cmd "refresh_after_replace_mul" refresh
run_tools_cmd "verify_after_replace_mul" verify

run_tools_cmd "clear" clear
run_tools_cmd "list_after_clear" list
run_tools_cmd "show_after_clear" show
run_tools_cmd "scope_after_clear" --scope
run_tools_cmd "refresh_after_clear" refresh
run_tools_cmd "verify_after_clear" verify

run_tools_cmd "delete" delete
run_tools_cmd "list_after_delete" list
run_tools_cmd "show_after_delete" show
run_tools_cmd "scope_after_delete" --scope
run_tools_cmd "refresh_after_delete" refresh
run_tools_cmd "verify_after_delete" verify

# edit not tested

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
