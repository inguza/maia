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

run_system_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_system_${test_id}" $MAIA system "$@"
}

# Test help output
run_system_cmd "help" --help

# Test show system prompt (may be empty or default)
run_system_cmd "show" show

# Test append text to system prompt
run_system_cmd "append_text" append "This is a system prompt line."

# Test show after append
run_system_cmd "show_after_append" show

# Test replace prompt content
run_system_cmd "replace_text" replace "This is replaced system prompt content."

# Test show after replace
run_system_cmd "show_after_replace" show

# Test clear prompt content (empties the prompt file)
run_system_cmd "clear_prompt" clear

# Test show after clear (should be empty)
run_system_cmd "show_after_clear" show

# Test append multiple lines from a here-doc (simulate file input)
run_system_cmd "append_multiline" append <<EOF
Line 1 of system prompt
Line 2 of system prompt
EOF

# Test show after multiline append
run_system_cmd "show_after_multiline_append" show

# Test delete prompt file
run_system_cmd "delete_prompt" delete

# Test show after delete (should handle missing prompt gracefully)
run_system_cmd "show_after_delete" show

# Test append with --scope home
run_system_cmd "append_scope_user" append --scope home "User scoped prompt line."

# Test append compose with --scope home
export EDITOR="$TEST_ROOT/mock_editor.sh"
run_system_cmd "append_scope_user" append --scope home +compose
unset EDITOR

# Test show with --scope user
run_system_cmd "show_scope_user" show --scope user

# Test append with --type files
run_system_cmd "show_type_files" --type files show
run_system_cmd "append_type_files" --type files append "Files type prompt content."

# Test show with --type files
run_system_cmd "show_type_files_after_append" --type files show
export EDITOR="$TEST_ROOT/mock_editor.sh"
run_system_cmd "append_scope_user_compose" append --scope home +compose
unset EDITOR

# Test edit command (opens editor on system prompt)
export EDITOR="$TEST_ROOT/mock_editor.sh"
run_system_cmd "edit" +edit
unset EDITOR

run_system_cmd "show_after_edit" show

# Test read command (simulate read from stdin by echo piped in)
echo "Read from stdin prompt line." | run_system_cmd "read_from_stdin" +read

# Test tool instructions a little
run_system_cmd "show_type_tools" --type tools show
run_system_cmd "append_type_files" --type tools "- One more generic tool instruction."
run_system_cmd "show_type_tools_after_append" --type tools show

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
