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

run_file_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_file_${test_id}" $MAIA file "$@"
}

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

echo "x1" > x1.txt
echo "x2" > x2.txt
echo "x3" > x3.txt
echo "y1" > y1.txt
echo "y2" > y2.txt

run_workspace_cmd "create_and_use_workspace" create ws
$MAIA session create testsession --workspace ws
export MAIA_SESSION=testsession

run_fileset_cmd "create_t1" create t1
run_fileset_cmd "create_t2" create t2
run_fileset_cmd "create_t3" create t3

run_file_cmd "file_remember_x1_t1" --filesets t1 remember x1.txt
run_file_cmd "file_list_after_remember_x1_t1_t1" --filesets t1 list
run_file_cmd "file_list_after_remember_x1_t1_t2" --filesets t2 list
run_file_cmd "file_list_after_remember_x1_t1_t3" --filesets t3 list
run_file_cmd "file_list_after_remember_x1_t1_all" --all list
run_file_cmd "file_remember_x2_t2" --filesets t2 remember x2.txt
run_file_cmd "file_list_after_remember_x2_t2_t1" --filesets t1 list
run_file_cmd "file_list_after_remember_x2_t2_t2" --filesets t2 list
run_file_cmd "file_list_after_remember_x2_t2_t3" --filesets t3 list
run_file_cmd "file_list_after_remember_x2_t2_all" --all list
run_file_cmd "file_remember_y1_t13" --filesets t1,t3 remember y1.txt
run_file_cmd "file_list_after_remember_y1_t13_t1" --filesets t1 list
run_file_cmd "file_list_after_remember_y1_t13_t2" --filesets t2 list
run_file_cmd "file_list_after_remember_y1_t13_t3" --filesets t3 list
run_file_cmd "file_list_after_remember_y1_t13_all" --all list
run_file_cmd "file_remember_y2_all" --all remember y2.txt
run_file_cmd "file_list_after_remember_y2_all_t1" --filesets t1 list
run_file_cmd "file_list_after_remember_y2_all_t2" --filesets t2 list
run_file_cmd "file_list_after_remember_y2_all_t3" --filesets t3 list
run_file_cmd "file_list_after_remember_y2_all_all" --all list

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
