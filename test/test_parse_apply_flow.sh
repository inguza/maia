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

export OPENAI_API_KEY=dummy

test_start

common_setup_output_dir
setup_maia_home
setup_mock_curl

# Create default workspace after MAIA home creation
$MAIA workspace create default > /dev/null 2>&1
$MAIA config --scope session auto_parse false

FIXTURE_DIR="$TEST_ROOT/parse_apply_flow/fixtures"

run_send_cmd() {
    local test_id="$1"
    shift
    run_and_check "send_${test_id}" $MAIA send "$@"
}

run_parse_cmd() {
    local test_id="$1"
    shift
    run_and_check "parse_${test_id}" $MAIA parse "$@"
}

run_change_cmd() {
    local test_id="$1"
    shift
    run_and_check "change_${test_id}" $MAIA change "$@"
}

run_history_cmd() {
    local test_id="$1"
    shift
    run_and_check "history_${test_id}" $MAIA history "$@"
}

run_file_cmd() {
    local test_id="$1"
    shift
    run_and_check "file_${test_id}" $MAIA file "$@"
}

run_cat_cmd() {
    local test_id="$1"
    local file_path="$2"
    run_and_check "cat_${test_id}" cat "$file_path"
}

# Step 1: Add file 1
encode_response_to_json "$FIXTURE_DIR/1-filenameknown.txt" "$FIXTURE_DIR/response_1.json"
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_1.json"
run_send_cmd "fixture1" "Dummy generate request."
unset MOCK_CURL_RESPONSE_FILE

run_history_cmd "after_send_1"

run_parse_cmd "parse_1"

run_change_cmd "list_pending_1" "list" "--pending"

run_change_cmd "show_1" "show"

run_change_cmd "apply_1" "apply"

run_file_cmd "apply_1" "list"

run_cat_cmd "parsed_testfile1_1" "testfile1.sh"

run_change_cmd "list_applied_1" "list" "--applied"

run_history_cmd "after_apply_1"

# Step 2: Add file 2
encode_response_to_json "$FIXTURE_DIR/2-filenameknown.txt" "$FIXTURE_DIR/response_2.json"
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_2.json"
run_send_cmd "fixture2" "Dummy generate request."
unset MOCK_CURL_RESPONSE_FILE

run_history_cmd "after_send_2"

run_parse_cmd "parse_2" "last"

run_change_cmd "list_pending_2" "list" "--pending"

run_change_cmd "show_2" "show"

run_change_cmd "apply_2" "apply" "--keep-history"

run_file_cmd "apply_2" "list"

run_cat_cmd "parsed_testfile1_2" "testfile1.sh"

run_change_cmd "list_applied_2" "list" "--applied"

run_history_cmd "after_apply_2"

# Step 3: Add file 3 (unknown filename, assign default)
encode_response_to_json "$FIXTURE_DIR/3-filenameunknown.txt" "$FIXTURE_DIR/response_3.json"
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_3.json"
run_send_cmd "fixture3" "Dummy generate request."
unset MOCK_CURL_RESPONSE_FILE

run_history_cmd "after_send_3"

run_parse_cmd "parse_3" "last" --force "testfile1.sh"

run_change_cmd "list_pending_3" "list" "--pending"

run_change_cmd "show_3" "show"

run_change_cmd "apply_3" "apply" "--keep-history" "--update-history"

run_cat_cmd "parsed_testfile1_3" "testfile1.sh"

run_change_cmd "list_applied_3" "list" "--applied"

run_history_cmd "after_apply_3"

# Step 4: Add file 4 (wrong filename, assign default)
encode_response_to_json "$FIXTURE_DIR/4-filenamewrong.txt" "$FIXTURE_DIR/response_4.json"
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_4.json"
run_send_cmd "fixture4" "Dummy generate request."
unset MOCK_CURL_RESPONSE_FILE

run_history_cmd "after_send_4"

run_parse_cmd "parse_4" "last" --force "testfile1.sh"

run_change_cmd "list_pending_4" "list" "--pending"

run_change_cmd "show_4" "show"

run_change_cmd "apply_4" "apply"

run_cat_cmd "parsed_testfile1_4" "testfile1.sh"

run_change_cmd "list_applied_4" "list" "--applied"

run_history_cmd "after_apply_4"

# Step 5: Add file 5 (wrong filename, assign default, replace entire file)
encode_response_to_json "$FIXTURE_DIR/5-filenamewrong.txt" "$FIXTURE_DIR/response_5.json"
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_5.json"
run_send_cmd "fixture5" "Dummy generate request."
unset MOCK_CURL_RESPONSE_FILE

run_history_cmd "after_send_5"

run_parse_cmd "parse_5" "last" --force "testfile1.sh"

run_change_cmd "list_pending_5" "list" "--pending"

run_change_cmd "show_5" "show"

run_change_cmd "apply_5" "apply"

run_cat_cmd "parsed_testfile1_5" "testfile1.sh"

run_change_cmd "list_applied_5" "list" "--applied"

run_history_cmd "after_apply_5"

# Step 6: Add change set with file-type sub-entries (no patch) to test apply error message formatting
# This test is supposed to show threecases:
#   file1 - identical file
#   file2 - new file
#   file3 - changed file
# Use fixture 6-1 two files no splice (existing files) and 6-2 three files no splice (new files with patches)
encode_response_to_json "$FIXTURE_DIR/6-1-twofiles-nosplice.txt" "$FIXTURE_DIR/response_6_1.json"
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_6_1.json"
run_send_cmd "fixture6_1" "Dummy generate request for existing files with no patch."
unset MOCK_CURL_RESPONSE_FILE

# Parse and apply the first set
run_parse_cmd "parse_6_1"
run_change_cmd "list_pending_6_1" "list" "--pending"
run_change_cmd "apply_6_1" "apply"
# This should generate two new files

encode_response_to_json "$FIXTURE_DIR/6-2-threefiles-nosplice.txt" "$FIXTURE_DIR/response_6_2.json"
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_6_2.json"
run_send_cmd "fixture6_2" "Dummy generate request for new files with patches."
unset MOCK_CURL_RESPONSE_FILE

# Parse and apply the second set
run_parse_cmd "parse_6_2"
# This should generate one new file and two patched
run_change_cmd "list_pending_6_2" "list" "--pending"
run_change_cmd "apply_6_2" "apply"

cleanup_mock_curl
cleanup_maia_home
common_cleanup_output_dir

test_end
