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
$MAIA workspace create ws
$MAIA session create default --workspace ws
export MAIA_SESSION=default

run_change_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_change_${test_id}" $MAIA change "$@"
}

# Test help output (short and long)
run_change_cmd "help_short" -h
run_change_cmd "help_long" --help


setup_changes_dir() {
    local changes_dir="$XMAIA_HOME/.maia/workspaces/ws/changes/default"
    mkdir -p "$changes_dir"

    # Create two mock change sets
    echo '{"type":"set","status":"pending"}' > "$changes_dir/20250513T142512-abcd1234-+-pending.json"
    echo '{"type":"patch","status":"pending","filename":"src/file1.txt"}' > "$changes_dir/20250513T142512-abcd1234-1-pending.json"
    echo 'Instruction text for the change set' > "$changes_dir/20250513T142512-abcd1234.txt"
    echo 'Patch content for file1' > "$changes_dir/20250513T142512-abcd1234-1-pending.patch"

    echo '{"type":"set","status":"pending"}' > "$changes_dir/20250513T142512-abcd1235-+-pending.json"
    echo '{"type":"shell","status":"pending","filename":""}' > "$changes_dir/20250513T142512-abcd1235-1-pending.json"
    echo 'sleep 3' > "$changes_dir/20250513T142512-abcd1235-1-pending.shell"
    echo 'echo Foo' >> "$changes_dir/20250513T142512-abcd1235-1-pending.shell"
}

# Setup changes directory with mock data

run_change_cmd "list_empty" list
run_change_cmd "list_all_empty" list --all

# Additional tests for change management

setup_changes_dir
set1=20250513T142512-abcd1234
set2=20250513T142512-abcd1235

show_x() {
    run_change_cmd "list_all_after_$1" list --all
    run_change_cmd "show_set_1_after_$1" show "${set1}"
    run_change_cmd "show_set_2_after_$1" show "${set2}"
    run_change_cmd "show_item_1_after_$1" show "${set1}-1"
    run_change_cmd "show_item_2_after_$1" show "${set2}-1"
}

# Test show commands
show_x setup

# Test edit command with assign-path
#run_change_cmd "edit_assign_path" edit --assign-path new/path "${set1}-1"
#show_x assign_path

# Test applied command
run_change_cmd "applied" applied "${set1}-1"
show_x applied

# Test pending command
run_change_cmd "pending" pending "${set1}-1"
show_x pending

# Test skipped command
run_change_cmd "skipped" skipped "${set1}-1"
show_x skipped

# Test finished command
run_change_cmd "finished" applied "${set1}-1"
show_x finished

# Test running command
run_change_cmd "running" applied "${set1}-1"
show_x running

# Test failed command
run_change_cmd "failed" applied "${set1}-1"
show_x failed

# Test run command
run_change_cmd "run" run "${set2}-1" &
sleep 0.5
show_x after_run
sleep 3
show_x after_run_3

# Test delete command
run_change_cmd "delete_fail" delete "${set1}-1"
show_x after_delete_1-1

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
