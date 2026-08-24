#!/usr/bin/env bash
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

source "$(dirname "$0")/common.sh"

test_start

common_setup_output_dir
setup_maia_home

run_fileset_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_fileset_${test_id}" $MAIA fileset "$@"
}

run_workspace_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_workspace_${test_id}" $MAIA workspace "$@"
}

# We just need a workspace to work in
$MAIA workspace create foo > /dev/null 2>&1
$MAIA session create testsession --workspace foo
export MAIA_SESSION=testsession

# Test list filesets (likely empty initially)
run_fileset_cmd "list" list

# Create, delete and more
run_fileset_cmd "create_foo" create foo
run_fileset_cmd "list_after_foo" list
run_fileset_cmd "show_foo" show foo
run_fileset_cmd "create_bar" create bar
run_fileset_cmd "list_after_bar" list
run_fileset_cmd "show_bar" show bar
run_fileset_cmd "readonly_foo" readonly foo
run_fileset_cmd "list_after_ro_foo" list
run_fileset_cmd "show_after_ro_foo" show foo
run_fileset_cmd "use_two" use foo,bar
run_workspace_cmd "show_ws_after_use_twoo" show

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
