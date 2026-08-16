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

# Create a fixtures directory inside OUTPUT_DIR for input JSON files
FIXTURE_DIR="$OUTPUT_DIR/fixtures"
mkdir -p "$FIXTURE_DIR"

# Prepare static fixture files for assistant responses
cat > "$FIXTURE_DIR/response_1.txt" <<EOF
Assistant response 1
EOF

cat > "$FIXTURE_DIR/response_2.txt" <<EOF
Assistant response 2
EOF

# For response 3, include fenced file snippet as part of assistant response
cat > "$FIXTURE_DIR/response_3.txt" <<EOF
Here is some sample text with a fenced file:
\`\`\`
file.txt
This is the file content
\`\`\`
EOF

cat > "$FIXTURE_DIR/response_4.txt" <<EOF
Assistant response 4
EOF

# Encode responses to JSON once, to be used as MOCK_CURL_RESPONSE_FILE
encode_response_to_json "$FIXTURE_DIR/response_1.txt" "$FIXTURE_DIR/response_1.json"
encode_response_to_json "$FIXTURE_DIR/response_2.txt" "$FIXTURE_DIR/response_2.json"
encode_response_to_json "$FIXTURE_DIR/response_3.txt" "$FIXTURE_DIR/response_3.json"
encode_response_to_json "$FIXTURE_DIR/response_4.txt" "$FIXTURE_DIR/response_4.json"

run_send_cmd() {
    local test_id="$1"
    shift
    run_and_check "send_history_${test_id}" $MAIA send "$@"
}

run_history_cmd() {
    local test_id="$1"
    shift
    run_and_check "history_${test_id}" $MAIA history "$@"
}

# Test popping before anything
run_history_cmd "pop_2_before_anything" pop 2
run_history_cmd "top_2_before_anything" top 2

# Add 4 different entries to the history
# Each send adds a user and assistant entry, so 4 sends mean 8 entries total.

# Entry 1: Some sample text (user message)
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_1.json"
run_send_cmd 1 "Some sample text"
unset MOCK_CURL_RESPONSE_FILE

# Entry 2: Some other sample text (user message)
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_2.json"
run_send_cmd 2 "Some other sample text"
unset MOCK_CURL_RESPONSE_FILE

# Entry 3: User message is simple text; assistant response includes fenced file snippet
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_3.json"
run_send_cmd 3 "Some sample text"
unset MOCK_CURL_RESPONSE_FILE

# Entry 4: Some further sample text (user message)
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_4.json"
run_send_cmd 4 "Some further sample text"
unset MOCK_CURL_RESPONSE_FILE

# Now run history command tests

# Show help (should exit non-zero and show usage on stderr)
set +e
run_history_cmd "help" -h
set -e

# Show all history (8 entries: user+assistant for each send)
run_history_cmd "show_all" show -
run_history_cmd "show_all_2" show all
run_history_cmd "show_all_3" show ''
run_history_cmd "show_all_4" -
run_history_cmd "show_all_5" all

# Show range 0-1 (first two entries, likely user msg 1 and assistant msg 1)
run_history_cmd "show_range_0_1" show 0-1
run_history_cmd "show_range_0_1_short" 0-1

# Show range 6-7 (last two entries, user msg 4 and assistant msg 4)
run_history_cmd "show_range_6_7" show 6-7

# Show range 1- (from index 1 to end)
run_history_cmd "show_range_1_to_end" show 1-

# Show range -2 (first 3 entries: 0,1,2)
run_history_cmd "show_range_minus_2" show -2

# Show last (last entry, index 7)
run_history_cmd "show_last" show last
run_history_cmd "show_last_2" show
run_history_cmd "show_last_3"

# Show last-2 (last 3 entries: 5,6,7)
run_history_cmd "show_last_minus_2" show last-2
run_history_cmd "show_last_minus_2_s" last-2

# Show user messages only - ranges as well
run_history_cmd "show_user_last_user" show --user
run_history_cmd "show_user_last_user_2" --user

run_history_cmd "show_user_range_0_3" show 0-3 --user
run_history_cmd "show_user_last" show last --user
run_history_cmd "show_user_last_2" show last-2 --user

# Show assistant messages only - ranges as well
run_history_cmd "show_assistant_all" show --assistant
run_history_cmd "show_assistant_range_2_5" show 2-5 --assistant
run_history_cmd "show_assistant_last" show last --assistant
run_history_cmd "show_assistant_last_2" show last-2 --assistant

# Show with both --user and --assistant (should show all)
run_history_cmd "show_both" show --user --assistant

# Pop last entry: pop removes last entry (which is assistant msg 4)
run_history_cmd "pop_1" pop

# Show full history after pop (7 entries left)
run_history_cmd "pop_1_show" show

# Pop last 2 entries (removes last two entries, e.g. 6 and 5)
run_history_cmd "pop_2" pop 2

# Show full history after pop 2 (5 entries left)
run_history_cmd "pop_2_show" show

# Add back entries 3 and 4 to enable further tests (send again)
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_3.json"
run_send_cmd "back_3" "Some sample text"
unset MOCK_CURL_RESPONSE_FILE

export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_4.json"
run_send_cmd "back_4" "Some further sample text"
unset MOCK_CURL_RESPONSE_FILE

# Top first entry (removes and prints entry 0 - user msg 1)
run_history_cmd "top_1" top

# Show full history after top 1 (should have 7 entries)
run_history_cmd "top_1_show" show

# Top first 2 entries (removes entries 1 and 2)
run_history_cmd "top_2" top 2

# Show full history after top 2 (should have 5 entries)
run_history_cmd "top_2_show" show

# Add back entries 0,1,2 to enable delete tests (send again)
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_1.json"
run_send_cmd "back_2_1" "Some sample text"
unset MOCK_CURL_RESPONSE_FILE

export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_2.json"
run_send_cmd "back_2_2" "Some other sample text"
unset MOCK_CURL_RESPONSE_FILE

export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_3.json"
run_send_cmd "back_2_3" "Some sample text"
unset MOCK_CURL_RESPONSE_FILE

# Delete a range (0-1) (should delete first two entries: user msg 1 and assistant msg 1)
run_history_cmd "delete_range_0_1" delete 0-1

# Show full history after delete 0-1
run_history_cmd "delete_range_0_1_show" show

# Delete range 2-3 (delete two entries somewhere in the middle)
run_history_cmd "delete_range_2_3" delete 2-3

# Show full history after delete 2-3
run_history_cmd "delete_range_2_3_show" show

# Add entries again to test prune
export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_1.json"
run_send_cmd "back_3_1" "Some sample text"
unset MOCK_CURL_RESPONSE_FILE

export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_2.json"
run_send_cmd "back_3_2" "Some other sample text"
unset MOCK_CURL_RESPONSE_FILE

export MOCK_CURL_RESPONSE_FILE="$FIXTURE_DIR/response_3.json"
run_send_cmd "back_3_3" "Some sample text"
unset MOCK_CURL_RESPONSE_FILE

# Prune a range with fenced content (likely entries 4 and 5)
run_history_cmd "prune_range_with_fenced" prune 4-5

# Show full history after prune range with fenced
run_history_cmd "prune_range_with_fenced_show" show

# Prune a range without fenced content (0-3)
run_history_cmd "prune_range_no_fenced" prune 0-3

# Show full history after prune range no fenced
run_history_cmd "prune_range_no_fenced_show" show

# Search keyword in history (keyword "sample")
run_history_cmd "search_keyword_sample" search sample

# Test 1: Show with --raw outputs full JSON array and includes correct entries
run_history_cmd "show_raw" show --raw
run_history_cmd "show_raw_user" show --user --raw
run_history_cmd "show_raw_assistant" show --assistant --raw
run_history_cmd "show_raw_both" show --user --assistant --raw

# Test 2: Search with --raw outputs full JSON array and respects role filters
run_history_cmd "search_raw" search sample --raw
run_history_cmd "search_raw_user" search sample --user --raw
run_history_cmd "search_raw_assistant" search sample --assistant --raw
run_history_cmd "search_raw_both" search sample --user --assistant --raw

# Test 3: Search with role filters returns only matching roles
run_history_cmd "search_user_only" search sample --user
run_history_cmd "search_assistant_only" search sample --assistant
run_history_cmd "search_both_roles" search sample --user --assistant

# Test 4: Show with various range formats combined with role filters
run_history_cmd "show_range_last_2_user" show last-2 --user
run_history_cmd "show_range_0_3_assistant" show 0-3 --assistant
run_history_cmd "show_range_1_to_end_both" show 1- --user --assistant

# Test 5: Verify indexing and numbering consistency in show output
run_history_cmd "show_indexing_test" show 0-7

# Test 6: Verify indexing and numbering consistency in search output
run_history_cmd "search_indexing_test" search sample

# Test 7: Search with keyword not found returns empty result gracefully
run_history_cmd "search_no_match" search "nonexistentkeyword"

# Test 8: Show with invalid range input should not crash (ok to print error), same with empty range
run_history_cmd "show_invalid_range" show "invalid"
run_history_cmd "show_empty_range" show ""

# Test 9: Show with both --user and --assistant flags behaves same as no role filter
run_history_cmd "show_both_flags" show --user --assistant

# Test 10: Search with both --user and --assistant flags behaves same as no role filter
run_history_cmd "search_both_flags" search sample --user --assistant

# Test 11: Show default (no args) uses last entry and outputs correctly
run_history_cmd "show_default" show

# Test 12: Search with keyword and no matches outputs nothing (no error)
run_history_cmd "search_keyword_no_results" search "unmatchablekeyword"

# Now test pruning

# Setup helper: add an assistant message with known content to prune
n=0
add_assistant_entry() {
    local user_msg="$1"
    local assistant_msg="$2"

    # Prepare dummy API response JSON with assistant message content
    local tmp_resp=$(mktemp)
    jq -n --arg content "$assistant_msg" '{
        choices: [{
            message: { role: "assistant", content: $content }
        }]
    }' > "$tmp_resp"

    export MOCK_CURL_RESPONSE_FILE="$tmp_resp"
    run_send_cmd "add_assistant_entry_$n" "$user_msg"
    n=$(( n + 1 ))
    unset MOCK_CURL_RESPONSE_FILE
    rm -f "$tmp_resp"
}

# Test prune --reduce (default prune) removes fenced blocks but keeps placeholders
run_history_cmd "prune_reduce" prune --reduce last
run_history_cmd "prune_reduce_show" show last

# Add a fresh assistant entry with fenced code block for testing
add_assistant_entry "User message for reduce prune" "Here is code:\n\`\`\`bash\necho hello\n\`\`\`\nEnd."

# Run prune --reduce explicitly on last entry
run_history_cmd "prune_explicit_reduce" prune last --reduce
run_history_cmd "prune_explicit_reduce_show" show last

# Test prune --cut replaces entire content with placeholder
add_assistant_entry "User message for cut prune" "This entire message will be replaced."

run_history_cmd "prune_cut" prune last --cut
run_history_cmd "prune_cut_show" show last

# Test prune --edit opens editor (simulate editor by overriding EDITOR)
add_assistant_entry "User message for edit prune" "This message contains old text."

# Run prune --edit last entry (should replace 'old' with 'new')
export EDITOR="$TEST_ROOT/mock_editor_sed.sh"
run_history_cmd "prune_edit" prune last --edit
unset EDITOR
run_history_cmd "prune_edit_show" show last


# Test prune with range to prune multiple entries with --cut
add_assistant_entry "User message A" "Message A content"
add_assistant_entry "User message B" "Message B content"

# Prune last two assistant messages with --cut
run_history_cmd "prune_cut_multiple" prune last-1 --cut
run_history_cmd "prune_cut_multiple_show" show last-1

# Clear history (wipe all entries)
run_history_cmd "clear" clear

# Show full history after clear (should be empty)
run_history_cmd "clear_show" show

# Clean up fixtures directory
rm -rf "$FIXTURE_DIR"

# Cleanup
cleanup_mock_curl
cleanup_maia_home
common_cleanup_output_dir

test_end
