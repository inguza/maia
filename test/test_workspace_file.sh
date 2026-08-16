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
echo "y3" > y3.txt

run_workspace_cmd "create_and_use_workspace" create ws --use

# Test list files (likely empty initially)
run_file_cmd "list" list

# Test remember files (add files to filesets)
run_file_cmd "remember_single" remember README.txt

run_file_cmd "list_after_remember_single" list

run_file_cmd "remember_multiple" remember x*.txt "y1.txt"

run_file_cmd "list_after_remember_multiple" list

run_file_cmd "remember_with_function_filter" remember "y2.txt:send_usage"

run_file_cmd "list_after_remember_with_function_filter" list

run_file_cmd "remember_with_pipe_filter" remember 'y3.txt|cat|grep "y3"'

run_file_cmd "list_after_remember_with_pipe_filter" list


# Test forget files (remove entries from filesets)
run_file_cmd "forget_multiple" forget "x*.txt"

run_file_cmd "list_after_forget_multiple" list

run_file_cmd "forget_function_filter" forget "*:*_usage"

run_file_cmd "list_after_forget_function_filter" list

run_file_cmd "list_add_again" add x1.txt x2.txt

run_file_cmd "list_after_add_2" list

# Test remove files (forget + delete files)
run_file_cmd "remove_single" remove x2.txt
run_and_check "ls" ls x*.txt
run_file_cmd "list_after_remove_single" list
run_and_check "ls_x" ls x*.txt

# Test remove something that should not be possible to remove
run_file_cmd "remove_with_pipe_filter" remove 'y3.txt|cat|grep "y3"'
if [ ! -e "y3.txt" ] ; then
    echo "Important error. Remove shall not remove if it is a filter!"
    exit 1
fi
run_file_cmd "list_after_remove_with_pipe_filter" list

run_and_check "ls_y" ls y*.txt

# Test list all files in filesets (default session workspace)
run_file_cmd "list_all" list --all

# Test list files in specific filesets
run_file_cmd "list_filesets" list --filesets default,tests

# Test content command to show file contents
run_file_cmd "content_file" content

run_file_cmd "content_all" content --all

# Test add alias for remember
run_file_cmd "add_alias" add x3.txt
run_file_cmd "list_after_add_alias" list

# Test delete alias for forget
run_file_cmd "delete_alias" delete x3.txt
run_file_cmd "list_after_delete_alias" list

# Test usage of --filesets option with remember and forget
run_file_cmd "remember_with_filesets" remember --filesets default y1.txt

run_file_cmd "forget_with_filesets" forget --filesets default "y1.txt"

# Test error handling: forget non-existing pattern
run_file_cmd "forget_non_existing" forget "non_existing_file.txt"

# Test forget with quoted patterns that include glob characters
run_file_cmd "forget_quoted_glob" forget "\"*backup*\""

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
