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

run_user_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_user_${test_id}" $MAIA user "$@"
}

# Test help output (short and long)
run_user_cmd "help_short" -h
run_user_cmd "help_long" --help

# Test show on empty outbox (should handle gracefully)
run_user_cmd "show_empty" show

# Append text messages
run_user_cmd "append1" append "This is a test user message 1."
run_user_cmd "show_after_append1" show

run_user_cmd "append2" append "This is a test user message 2."
run_user_cmd "show_after_append2" show

# Append multiple lines by simulating file input or here-doc
run_user_cmd "append_multiline" append "$(printf 'Line 1\nLine 2\nLine 3')"
run_user_cmd "show_after_append_multiline" show

# Replace outbox content
run_user_cmd "replace" replace "This is a replacement text."
run_user_cmd "show_after_replace" show

# Clear outbox (removes content but keeps file)
run_user_cmd "clear" clear
run_user_cmd "show_after_clear" show

# Append after clear
run_user_cmd "append_after_clear" append "Message after clear."
run_user_cmd "show_after_append_after_clear" show

# Delete outbox (removes file)
run_user_cmd "delete" delete
run_user_cmd "show_after_delete" show

# Append several things
tmpfile1=$(mktemp)
tmpfile2=$(mktemp)
echo "Content of file 1" > "$tmpfile1"
echo "Content of file 2" > "$tmpfile2"

run_user_cmd "append_several" append "This is a test" $tmpfile1 "and some more content" "" "" "And more" $tmpfile2 "LAst things"
rm -f "$tmpfile1" "$tmpfile2"
run_user_cmd "show_after_several" show

# Test behavior when no command but text argument is given (should append)
run_user_cmd "implicit_append_text" "Implicit append message."
run_user_cmd "show_after_implicit_append_text" show

# Test behavior when no command but file argument is given (simulate with temp file)
tmpfile=$(mktemp)
echo "File content for implicit append" > "$tmpfile"
run_user_cmd "implicit_append_file" "$tmpfile"
run_user_cmd "show_after_implicit_append_file" show
rm -f "$tmpfile"

# Test append read (read from stdin)
echo "Message read from stdin" | run_user_cmd "append_read" append +read
run_user_cmd "show_after_append_read" show

# Test append compose (interactive editor) - mocked with existing mock_editor.sh
export EDITOR="$TEST_ROOT/mock_editor.sh"
run_user_cmd "append_compose" append +compose
run_user_cmd "show_after_append_compose" show

# Test append with inline edit token (should open editor inline)
run_user_cmd "append_inline_edit" append "Start text" +edit "More text"
run_user_cmd "show_after_append_inline_edit" show

# Test append complex inline edit scenario with multiple text args around edit token
run_user_cmd "append_inline_edit_complex" append "some text moretext" +edit "something"
run_user_cmd "show_after_append_inline_edit_complex" show

# Test edit subcommand (opens editor on outbox)
run_user_cmd "edit_command" +edit
run_user_cmd "show_after_edit_command" show

unset EDITOR

# Test multiple appends and then show
run_user_cmd "append3" append "Third message appended."
run_user_cmd "append4" append "Fourth message appended."
run_user_cmd "show_after_append3_and_4" show

# Test replace after multiple appends
run_user_cmd "replace_after_appends" replace "Replaced content after multiple appends."
run_user_cmd "show_after_replace_after_appends" show

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
