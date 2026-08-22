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

run_snippet_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_snippet_${test_id}" $MAIA snippet "$@"
}

# Test help output
run_snippet_cmd "help" --help

# Test list snippets (likely empty initially)
run_snippet_cmd "list" list

run_snippet_cmd "add1" add test1 "This is a test 1"
run_snippet_cmd "show1" show test1
run_snippet_cmd "implshow1" test1
run_snippet_cmd "list_after_add1" list

run_snippet_cmd "add2" add test2 "This is a test 2"
run_snippet_cmd "show2" show test2
run_snippet_cmd "implshow2" test2
run_snippet_cmd "list_after_add1_and_add2" list

run_snippet_cmd "append1" append test1 "This is a test to append 1"
run_snippet_cmd "show1_after_append1" show test1

# Test edit subcommand (opens editor on snippet file)
export EDITOR="$TEST_ROOT/mock_editor.sh"
run_snippet_cmd "edit1" edit test1
run_snippet_cmd "show_after_edit1" show test1

# Test append with inline edit token (should open editor inline)
run_snippet_cmd "append_inline_edit" append test1 "Start snippet text" +edit "More snippet text"
run_snippet_cmd "show_after_append_inline_edit" show test1

# Test append complex inline edit scenario with multiple text args around edit token
run_snippet_cmd "append_inline_edit_complex" append test1 "some text moretext" +edit "something"
run_snippet_cmd "show_after_append_inline_edit_complex" show test1

unset EDITOR

run_snippet_cmd "delete2" delete test2
run_snippet_cmd "list_after_add1_and_add2_and_delete2" list

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
