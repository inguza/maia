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

run_count_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_count_${test_id}" $MAIA count "$@"
}

# Test help output for count command
run_count_cmd "help" --help

# Test count with no arguments (should print usage or error)
run_count_cmd "no_args"

# Test count with a single word argument
run_count_cmd "single_word" Hello

# Test count with multiple text arguments
run_count_cmd "multiple_words" Hello "world!" "This is a test."

# Test count with a quoted string argument
run_count_cmd "quoted_string" '"This is a quoted string."'

export EDITOR="$TEST_ROOT/mock_editor.sh"
# Test count with the command 'compose' argument
run_count_cmd "command_compose" compose

# Test count with the command 'read' argument
echo "Testing" | run_count_cmd "command_read" read

# Test count with the command 'edit' argument
run_count_cmd "command_edit" edit
unset EDITOR

# Test count with --model option set to each supported model
for model in gpt-4 gpt-4-32k gpt-3.5-turbo gpt-4.1-mini; do
    run_count_cmd "model_${model//./_}" --model "$model" "This is a test for model $model."
done

# Test count with multiple text and file arguments combined
# Create temporary files for testing
tmpfile1=$(mktemp)
tmpfile2=$(mktemp)
echo "This is file one." > "$tmpfile1"
echo "File two content." > "$tmpfile2"

run_count_cmd "multiple_text_and_files" "Hello world" "$tmpfile1" "$tmpfile2"

# Cleanup temporary files
rm -f "$tmpfile1" "$tmpfile2"

# Test count with invalid model (should error)
run_count_cmd "invalid_model" --model invalid-model "Test with invalid model"

# Test count with --file-handling option (valid values)
for mode in DEFAULT BEFORE APPEND; do
    run_count_cmd "file_handling_${mode,,}" --file-handling "$mode" "Testing file handling mode $mode"
done

# Test count with --file-handling option (invalid value, should error)
run_count_cmd "file_handling_invalid" --file-handling INVALID "Testing invalid file handling mode"

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
