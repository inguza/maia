#!/usr/bin/env bash
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

# Source common helpers
source "$(dirname "$0")/common.sh"

test_start

# Setup output directory
common_setup_output_dir

# Setup isolated MAIA home environment
setup_maia_home

# Helper to run a send command and check output, request, and headers
run_send_cmd() {
    local test_id="$1"
    shift

    # Run the maia send command without --dry-run or --response-file
    run_and_check "test_send_${test_id}" $MAIA send "$@"
}

# Helper to run a send command and check output, request, and headers
run_user_cmd() {
    local test_id="$1"
    shift

    # Run the maia send command without --dry-run or --response-file
    run_and_check "test_user_${test_id}" $MAIA user "$@"
}

# Initialize mock curl
setup_mock_curl

# Predefine canned response files for tests
declare -A canned_responses=(
    ["default"]="$TEST_ROOT/send/responses/openai_success.json"
    ["aws_success"]="$TEST_ROOT/send/responses/aws_success_bedrock.json"
    ["openai_auth_error"]="$TEST_ROOT/send/responses/openai_error_auth.json"
    ["openai_rate_limit_error"]="$TEST_ROOT/send/responses/openai_error_rate_limit.json"
    ["openai_invalid_request_error"]="$TEST_ROOT/send/responses/openai_error_invalid_request.json"
    ["openai_malformed"]="$TEST_ROOT/send/responses/openai_malformed_response.json"
    ["openai_empty"]="$TEST_ROOT/send/responses/openai_empty_response.json"
    ["aws_throttling_error"]="$TEST_ROOT/send/responses/aws_error_throttling.json"
    ["aws_access_denied_error"]="$TEST_ROOT/send/responses/aws_error_access_denied.json"
    ["aws_malformed"]="$TEST_ROOT/send/responses/aws_malformed_response.json"
    ["aws_empty"]="$TEST_ROOT/send/responses/aws_empty_response.json"
)

# The API types to test, using config to set API type
api_types_and_configs=(
    "AUTODETECT"
    "OPENAI_CHAT_COMPLETIONS"
    "AWS_BEDROCK_CONVERSE"
)

# Test 1: show help for send command (no API type flag) — no request expected
run_and_check "help" $MAIA send -h

unset LANG
unset LC_NUMERIC
# Loop over API types for main tests
for api in "${api_types_and_configs[@]}"; do
    # Just to remove things from previous API
    $MAIA history clear
    #
    suffix=""
    response_file="${canned_responses[default]}"
    suffix="_api_${api,,}"
    if [[ "$api" == "AWS_BEDROCK_CONVERSE" ]]; then
        response_file="${canned_responses[aws_success]}"
	export AWS_ACCESS_KEY_ID="mockedapikey"
	export AWS_SECRET_ACCESS_KEY="mockedsecret"
	export AWS_SESSION_TOKEN="mockedtoken"
	unset OPENAI_API_KEY
    else
	export OPENAI_API_KEY="mockedapikey"
	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_SESSION_TOKEN
    fi

    # Set API type in config
    $MAIA config api_type "$api"

    # Set canned response override for this test invocation
    export MOCK_CURL_RESPONSE_FILE="$response_file"

    # Test 2: attempt to send with no arguments (should error, but credentials provided)
    run_send_cmd "no_args${suffix}"

    # Test 3: send with appended text arguments
    run_send_cmd "text${suffix}" "Hello, AI!"
    # Should give empty output
    run_user_cmd "text${suffix}"

    export LANG=sv_SE.utf8
    run_send_cmd "text_loc${suffix}" "Hello, AI!"
    unset LANG

    # Test 4: send with model override
    run_send_cmd "model_override${suffix}" --model gpt-4 "Test model override"

    # Test 5: send with temperature override
    run_send_cmd "temperature_override${suffix}" --temperature 0.1 "Test temperature override"

    # Test 6: send with file handling mode override (valid modes)
    run_send_cmd "file_handling_default${suffix}" --file-handling DEFAULT "Test file handling default"
    run_send_cmd "file_handling_before${suffix}" --file-handling BEFORE "Test file handling before"
    run_send_cmd "file_handling_append${suffix}" --file-handling APPEND "Test file handling append"

    # Test 7: send with file handling mode override (invalid mode - falls back to DEFAULT)
    run_send_cmd "file_handling_invalid${suffix}" --file-handling INVALID "Test file handling invalid"
    # Should give output
    run_user_cmd "file_handling_invalid${suffix}"

    # Test 8: send with a custom prompt file appended
    tmp_prompt=$(mktemp)
    echo "Test prompt content" > "$tmp_prompt"
    run_send_cmd "custom_prompt${suffix}" "$tmp_prompt"
    run_send_cmd "multi_type_prompt${suffix}" "This is a start" "$tmp_prompt" "Something more"
    rm -f "$tmp_prompt"

    # Test unknown option (should error)
    run_send_cmd "unknown_option${suffix}" --unknown-flag

    # Test empty prompt file (should error, but the check is after credentials so they must be provided)
    tmp_empty_prompt=$(mktemp)
    : > "$tmp_empty_prompt"
    run_send_cmd "empty_prompt_file${suffix}" "$tmp_empty_prompt"
    rm -f "$tmp_empty_prompt"

    # Clear canned response override after iteration
    unset MOCK_CURL_RESPONSE_FILE

    # Specific error cases for OPENAI
    if [[ "api" == "OPENAI_CHAT_COMPLETIONS" ]]; then
	# Test error handling for OpenAI errors
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[openai_auth_error]}"
	run_send_cmd "openai_auth_error" "Test auth error"
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[openai_rate_limit_error]}"
	run_send_cmd "openai_rate_limit_error" "Test rate limit error"
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[openai_invalid_request_error]}"
	run_send_cmd "openai_invalid_request_error" "Test invalid request error"
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[openai_malformed]}"
	run_send_cmd "openai_malformed_response" "Test malformed response"
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[openai_empty]}"
	run_send_cmd "openai_empty_response" "Test empty response"
    fi
    # Specific error cases for AWS
    if [[ "api" == "AWS_BEDROCK_CONVERSE" ]]; then
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[aws_throttling_error]}"
	run_send_cmd "aws_throttling_error" "Test AWS throttling error"
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[aws_access_denied_error]}"
	run_send_cmd "aws_access_denied_error" "Test AWS access denied error"
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[aws_malformed]}"
	run_send_cmd "aws_malformed_response" "Test AWS malformed response"
	export MOCK_CURL_RESPONSE_FILE="${canned_responses[aws_empty]}"
	run_send_cmd "aws_empty_response" "Test AWS empty response"
    fi

    # Test the send hook
    unset OPENAI_API_KEY
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    $MAIA config send_hook "$TEST_ROOT/send/hook.sh"
    export MOCK_CURL_RESPONSE_FILE="$response_file"
    run_send_cmd "with_hook${suffix}" "Hello, AI!"
    $MAIA config unset send_hook
done

# Reset API type to default AUTODETECT
$MAIA config unset api_type
export OPENAI_API_KEY="mockedapikey"

# Cleanup mock curl env, MAIA home, and output
cleanup_mock_curl
cleanup_maia_home
common_cleanup_output_dir

test_end
