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
$MAIA session create --workspace ws default
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
    echo 'type: set' > "$changes_dir/20250513T142512-abcd1234-+-pending.myl"
    echo 'type: patch' > "$changes_dir/20250513T142512-abcd1234-1-pending.myl"
    echo 'filename: src/file1.txt' >> "$changes_dir/20250513T142512-abcd1234-1-pending.myl"
    echo 'Instruction text for the change set' > "$changes_dir/20250513T142512-abcd1234.txt"
    echo 'Patch content for file1' > "$changes_dir/20250513T142512-abcd1234-1-pending.patch"

    echo 'type: set' > "$changes_dir/20250513T142512-abcd1235-+-pending.myl"
    echo 'type: shell' > "$changes_dir/20250513T142512-abcd1235-1-pending.myl"
    echo 'filename:' >> "$changes_dir/20250513T142512-abcd1235-1-pending.myl"
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
run_change_cmd "pending_set" pending "${set1}"
show_x pending

# Test skipped command
run_change_cmd "skipped" skipped "${set1}-1"
show_x skipped

# Test finished command
run_change_cmd "finished" finished "${set2}-1"
show_x finished

# Test running command
run_change_cmd "running" running "${set2}-1"
show_x running

# Test failed command
run_change_cmd "failed" failed "${set2}-1"
show_x failed

# Test failed command
run_change_cmd "pending2" pending "${set2}-1"

# Test run command
run_change_cmd "run" run "${set2}-1" &
sleep 0.5
show_x after_run
sleep 4
show_x after_run_3

# Set change tests
setup_set_change_cases() {
    local changes_dir="$XMAIA_HOME/.maia/workspaces/ws/changes/default"
    local set_run_shell=20250513T142512-abcd1240
    local set_apply_patch=20250513T142512-abcd1241
    local set_run_pending_patch=20250513T142512-abcd1242
    local set_run_skipped_patch=20250513T142512-abcd1243
    local set_run_failed=20250513T142512-abcd1244
    local set_skip_all=20250513T142512-abcd1245
    local set_finished_mixed=20250513T142512-abcd1246
    local set_empty=20250513T142512-abcd1247
    local set_run_two_shells_patch=20250513T142512-abcd1248
    local set_run_two_shells=20250513T142512-abcd1249
    echo 'type: set' > "$changes_dir/$set_run_shell-+-pending.myl"
    echo 'type: shell' > "$changes_dir/$set_run_shell-1-pending.myl"
    echo 'echo set-run-shell' > "$changes_dir/$set_run_shell-1-pending.shell"
    echo 'type: set' > "$changes_dir/$set_apply_patch-+-pending.myl"
    echo 'type: patch' > "$changes_dir/$set_apply_patch-1-pending.myl"
    echo 'filename: set-cases/applied.txt' >> "$changes_dir/$set_apply_patch-1-pending.myl"
    echo 'MAIA-EMPTY-FILE: set-cases/applied.txt' > "$changes_dir/$set_apply_patch-1-pending.patch"
    echo 'type: set' > "$changes_dir/$set_run_pending_patch-+-pending.myl"
    echo 'type: shell' > "$changes_dir/$set_run_pending_patch-1-pending.myl"
    echo 'echo set-run-with-pending-patch' > "$changes_dir/$set_run_pending_patch-1-pending.shell"
    echo 'type: patch' > "$changes_dir/$set_run_pending_patch-2-pending.myl"
    echo 'filename: set-cases/pending.txt' >> "$changes_dir/$set_run_pending_patch-2-pending.myl"
    echo 'MAIA-EMPTY-FILE: set-cases/pending.txt' > "$changes_dir/$set_run_pending_patch-2-pending.patch"
    echo 'type: set' > "$changes_dir/$set_run_skipped_patch-+-pending.myl"
    echo 'type: shell' > "$changes_dir/$set_run_skipped_patch-1-pending.myl"
    echo 'echo set-run-with-skipped-patch' > "$changes_dir/$set_run_skipped_patch-1-pending.shell"
    echo 'type: patch' > "$changes_dir/$set_run_skipped_patch-2-skipped.myl"
    echo 'filename: set-cases/skipped.txt' >> "$changes_dir/$set_run_skipped_patch-2-skipped.myl"
    echo 'type: set' > "$changes_dir/$set_run_failed-+-pending.myl"
    echo 'type: shell' > "$changes_dir/$set_run_failed-1-pending.myl"
    echo 'false' > "$changes_dir/$set_run_failed-1-pending.shell"
    echo 'type: patch' > "$changes_dir/$set_run_failed-2-pending.myl"
    echo 'filename: set-cases/failed-other.txt' >> "$changes_dir/$set_run_failed-2-pending.myl"
    echo 'MAIA-EMPTY-FILE: set-cases/failed-other.txt' > "$changes_dir/$set_run_failed-2-pending.patch"
    echo 'type: set' > "$changes_dir/$set_skip_all-+-pending.myl"
    echo 'type: patch' > "$changes_dir/$set_skip_all-1-pending.myl"
    echo 'type: shell' > "$changes_dir/$set_skip_all-2-pending.myl"
    echo 'echo not-run' > "$changes_dir/$set_skip_all-2-pending.shell"
    echo 'type: set' > "$changes_dir/$set_finished_mixed-+-pending.myl"
    echo 'type: patch' > "$changes_dir/$set_finished_mixed-1-pending.myl"
    echo 'type: shell' > "$changes_dir/$set_finished_mixed-2-pending.myl"
    echo 'echo not-run' > "$changes_dir/$set_finished_mixed-2-pending.shell"
    echo 'type: set' > "$changes_dir/$set_empty-+-pending.myl"
    echo 'type: set' > "$changes_dir/$set_run_two_shells_patch-+-pending.myl"
    echo 'type: shell' > "$changes_dir/$set_run_two_shells_patch-1-pending.myl"
    echo 'echo first-shell-with-patch' > "$changes_dir/$set_run_two_shells_patch-1-pending.shell"
    echo 'type: shell' > "$changes_dir/$set_run_two_shells_patch-2-pending.myl"
    echo 'echo second-shell-with-patch' > "$changes_dir/$set_run_two_shells_patch-2-pending.shell"
    echo 'type: patch' > "$changes_dir/$set_run_two_shells_patch-3-pending.myl"
    echo 'filename: set-cases/two-shells-patch.txt' >> "$changes_dir/$set_run_two_shells_patch-3-pending.myl"
    echo 'MAIA-EMPTY-FILE: set-cases/two-shells-patch.txt' > "$changes_dir/$set_run_two_shells_patch-3-pending.patch"
    echo 'type: set' > "$changes_dir/$set_run_two_shells-+-pending.myl"
    echo 'type: shell' > "$changes_dir/$set_run_two_shells-1-pending.myl"
    echo 'echo first-of-two-shells' > "$changes_dir/$set_run_two_shells-1-pending.shell"
    echo 'type: shell' > "$changes_dir/$set_run_two_shells-2-pending.myl"
    echo 'echo second-of-two-shells' > "$changes_dir/$set_run_two_shells-2-pending.shell"
}

setup_set_change_cases
set_run_shell=20250513T142512-abcd1240
set_apply_patch=20250513T142512-abcd1241
set_run_pending_patch=20250513T142512-abcd1242
set_run_skipped_patch=20250513T142512-abcd1243
set_run_failed=20250513T142512-abcd1244
set_skip_all=20250513T142512-abcd1245
set_finished_mixed=20250513T142512-abcd1246
set_empty=20250513T142512-abcd1247
set_run_two_shells_patch=20250513T142512-abcd1248
set_run_two_shells=20250513T142512-abcd1249

show_set_x() {
    local test_id="$1"
    local set_id="$2"
    run_change_cmd "list_all_after_set_$test_id" list --all
    run_change_cmd "show_set_after_$test_id" show "$set_id"
}

run_change_cmd "set_run_shell" run "$set_run_shell"
show_set_x run_shell "$set_run_shell"
run_change_cmd "set_apply_patch" apply "$set_apply_patch"
show_set_x apply_patch "$set_apply_patch"
run_change_cmd "set_run_pending_patch" run "$set_run_pending_patch"
show_set_x run_pending_patch "$set_run_pending_patch"
run_change_cmd "set_skip_patch_subchange" skipped "$set_run_skipped_patch-2"
show_set_x skip_patch "$set_run_skipped_patch"
run_change_cmd "set_run_skipped_patch" run "$set_run_skipped_patch"
show_set_x run_skipped_patch "$set_run_skipped_patch"
run_change_cmd "set_run_failed" run "$set_run_failed"
show_set_x run_failed "$set_run_failed"
run_change_cmd "skip_failed_other" skipped "$set_run_failed-2"
show_set_x skip_failed_other "$set_run_failed"
run_change_cmd "set_skip_all" skipped "$set_skip_all"
show_set_x skip_all "$set_skip_all"
run_change_cmd "set_finished_mixed" finished "$set_finished_mixed"
show_set_x finished_mixed "$set_finished_mixed"
run_change_cmd "skip_finished_other" skipped "$set_finished_mixed-1"
show_set_x skip_finished_other "$set_finished_mixed"
run_change_cmd "set_empty" run "$set_empty"
show_set_x empty "$set_empty"
run_change_cmd "set_run_two_shells_patch" run "$set_run_two_shells_patch"
show_set_x run_two_shells_patch "$set_run_two_shells_patch"
run_change_cmd "set_run_two_shells" run "$set_run_two_shells"
show_set_x run_two_shells "$set_run_two_shells"

# Test delete command
run_change_cmd "delete_fail" delete "${set1}-1"
show_x after_delete_1-1

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
