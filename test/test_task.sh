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
$MAIA session create default

run_task_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_task_${test_id}" $MAIA task "$@"
}

# Test help output
run_task_cmd "help" --help

# Test list files (likely empty initially)
run_task_cmd "list_empty" list

run_task_cmd "task-1" create "Test task 1"
run_task_cmd "task-1-list" list
run_task_cmd "task-1-remove" remove task-1
run_task_cmd "task-1r-list" list

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
