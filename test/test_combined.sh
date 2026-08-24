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

mkdir x
echo "x1" > x/1.txt
echo "x2" > x/2.txt
echo "x3" > x/3.txt
echo "x4" > x/4.txt
echo "x5" > x/5.txt

# Helper to run a session command and check output
run_session_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_session_${test_id}" $MAIA session "$@"
}

run_workspace_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_workspace_${test_id}" $MAIA workspace "$@"
}

run_fileset_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_fileset_${test_id}" $MAIA fileset "$@"
}

run_file_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_file_${test_id}" $MAIA file "$@"
}

run_send_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_send_${test_id}" $MAIA send "$@"
}

run_count_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_count_${test_id}" $MAIA count "$@"
}

run_tool_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_tool_${test_id}" $MAIA tool "$@"
}

run_skill_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_skill_${test_id}" $MAIA skill "$@"
}

run_history_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_history_${test_id}" $MAIA history "$@"
}

# Initialize mock curl
setup_mock_curl

declare -A canned_responses=(
    ["default"]="$TEST_ROOT/send/responses/openai_success.json"
    ["aws_success"]="$TEST_ROOT/send/responses/aws_success_bedrock.json"
    )
api_types_and_configs=(
    "AUTODETECT"
    "OPENAI_CHAT_COMPLETIONS"
    "AWS_BEDROCK_CONVERSE"
)

run_workspace_cmd "create_and_use_workspace" create ws

# Test 2: create a new session named 'foo'
run_session_cmd "create_foo" create foo --workspace ws
export MAIA_SESSION=foo
run_session_cmd "show_after_foo" show foo

cd x
run_file_cmd "add_file_x1" add 1.txt
cd ..

# Loop over API types for main tests for sending to test sending
for api in "${api_types_and_configs[@]}"; do
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

    # Test 3: send with appended text arguments
    run_send_cmd "text${suffix}" "Hello, AI!"
    run_tool_cmd "enable_pipe_seq_tool${suffix}_1" enable core-pipe core-sequence
    run_send_cmd "tool_text${suffix}" "Hello again, AI!"
    run_tool_cmd "delete_pipe_seq_tool${suffix}_1" delete
    run_skill_cmd "skill_avail_pipe_seq_tool${suffix}_1" allow file
    run_send_cmd "skill_avail_text${suffix}" "Hello with skills avail, AI!"
    run_skill_cmd "skill_avail_pipe_seq_tool${suffix}_2" allow sequence
    run_skill_cmd "skill_remember_pipe_seq_tool${suffix}_1" remember file
    run_send_cmd "skill_remember_text${suffix}" "Hello with skills memory, AI!"
    run_tool_cmd "enable_pipe_seq_tool${suffix}_2" enable core-pipe core-sequence
    run_send_cmd "skill_remember_pipe_text${suffix}" "Hello with skills memory and tools, AI!"
    run_tool_cmd "delete_pipe_seq_tool${suffix}_2" delete
    run_skill_cmd "skill_delete_seq_tool${suffix}_1" delete

    # Test 6: send with file handling mode override (valid modes)
    run_send_cmd "file_handling_default${suffix}" --file-handling DEFAULT "Test file handling default"
    run_count_cmd "count_file_handling_default${suffix}" --file-handling DEFAULT "Test file handling default"
    run_send_cmd "file_handling_before${suffix}" --file-handling BEFORE "Test file handling before"
    run_count_cmd "count_file_handling_before${suffix}" --file-handling BEFORE "Test file handling before"
    run_send_cmd "file_handling_append${suffix}" --file-handling APPEND "Test file handling append"
    run_count_cmd "count_file_handling_append${suffix}" --file-handling APPEND "Test file handling append"

    # Test 7: tool and skill support
    run_tool_cmd "enable_pipe_seq_tool${suffix}_3" enable core-pipe core-sequence
    run_tool_cmd "enable_pipe_seq_tool_show${suffix}_2" show
    run_skill_cmd "skill_avail_pipe_seq_tool${suffix}_3" allow file sequence
    run_skill_cmd "skill_remember_pipe_seq_tool${suffix}_2" remember file
    run_skill_cmd "enable_pipe_seq_tool_show${suffix}_3" show
    run_send_cmd "tool_file_handling_default${suffix}" --file-handling DEFAULT "Test tool and file handling default"
    run_count_cmd "tool_count_file_handling_default${suffix}" --file-handling DEFAULT "Test tool and file handling default"
    run_send_cmd "tool_file_handling_before${suffix}" --file-handling BEFORE "Test tool and file handling before"
    run_count_cmd "tool_count_file_handling_before${suffix}" --file-handling BEFORE "Test tool and file handling before"
    run_send_cmd "tool_file_handling_append${suffix}" --file-handling APPEND "Test tool and file handling append"
    run_count_cmd "tool_count_file_handling_append${suffix}" --file-handling APPEND "Test tool and file handling append"
    run_tool_cmd "enable_pipe_seq_tool${suffix}_4" delete
    run_history_cmd "history_clear${suffix}" clear
    run_skill_cmd "skill_delete_seq_tool${suffix}_2" delete
    
    unset MOCK_CURL_RESPONSE_FILE
done

# Test 3: list sessions again, should show 'foo'
run_session_cmd "list_after_create" files
run_session_cmd "content_after_create" content

# Create a new session as a copy of the old
run_session_cmd "create_bar" create bar foo
export MAIA_SESSION=foo

run_session_cmd "show_after_bar" show bar
run_session_cmd "content_after_bar" content

# Test that __SESSIOM_NAME__ is shown properly as ro and not
run_fileset_cmd "ro_bar" ro bar
run_session_cmd "show_after_ro_bar" show bar
run_fileset_cmd "rw_bar" rw bar
run_session_cmd "show_after_rw_bar" show bar

# Test 4: use session 'foo'
export MAIA_SESSION=foo
run_session_cmd "show_after_use_foo" show
run_session_cmd "set_resolve" set --resolve
run_session_cmd "show_after_resolve" show

# Test that foo is shown properly as ro and not
run_fileset_cmd "ro_foo" ro foo
run_session_cmd "show_after_ro_foo" show
run_fileset_cmd "rw_foo" rw foo
run_session_cmd "show_after_rw_foo" show

run_fileset_cmd "use_two" use foo,bar
run_session_cmd "show_after_use_two" show
run_fileset_cmd "use_foo_again" use foo

run_fileset_cmd "use_session_name_not_allowed" use __SESSION_NAME__

# Test list filesets initially (likely empty or default)
run_fileset_cmd "list_empty" list

# Test create a new fileset named 'myfileset'
run_fileset_cmd "create_myfileset" create myfileset

# Test list after creation (should include 'myfileset')
run_fileset_cmd "list_after_create" list
run_fileset_cmd "list_all_after_create" list --all

# We only test once, because it is session info that is updated anyway
# Test use fileset 'myfileset'
run_fileset_cmd "use_myfileset" use myfileset
run_fileset_cmd "list_all_after_use_myfileset" list --all
run_workspace_cmd "show_after_use_myfileset" show
run_session_cmd "show_after_use_myfileset" show

# Test show contents of 'myfileset' (should be empty)
run_fileset_cmd "show_myfileset" show myfileset

# Test clear 'myfileset' (clears entries)
run_fileset_cmd "clear_myfileset" clear myfileset

# Test delete 'myfileset'
run_fileset_cmd "delete_myfileset" delete myfileset

# Test list after deletion (should not include 'myfileset')
run_fileset_cmd "list_after_delete" list

# Test more fileset handling
run_fileset_cmd "create_myfileset2" create myfileset2
run_fileset_cmd "list_after_create2" list
run_fileset_cmd "show_after_create2" show myfileset2
run_fileset_cmd "create_myfileset3" create myfileset3
run_fileset_cmd "list_after_create3" list
run_fileset_cmd "show_after_create3" show myfileset3
run_session_cmd "set_no_filesets" set --filesets ""
run_session_cmd "show_after_set_none" show
run_session_cmd "set_two_filesets" set --filesets "myfileset2,myfileset3"
run_session_cmd "show_after_set_two" show
run_file_cmd "add_x2" add x/2.txt
run_fileset_cmd "show_2_after_add_x2" show myfileset2
run_fileset_cmd "show_3_after_add_x2" show myfileset3
run_session_cmd "show_after_x2" show
run_session_cmd "content_after_x2" content
# Test extra send filesets
run_fileset_cmd "create_myextrafileset1" create myextrafileset1
run_fileset_cmd "use_myextra1" use myextrafileset1
run_file_cmd "add_x3" add x/3.txt
run_session_cmd "set_one_and_extra" set --filesets "myfileset2" --extra "myextrafileset1"
run_session_cmd "show_after_one_and_extra" show
run_session_cmd "content_after_one_and_extra" content
run_file_cmd "add_x4" add x/4.txt
run_fileset_cmd "show_2_after_add_x4" show myfileset2
run_fileset_cmd "show_3_after_add_x4" show myfileset3
run_fileset_cmd "show_e1_after_add_x4" show myextrafileset1
# Test read-only filesets
run_fileset_cmd "create_myfileset4" create myfileset4
run_fileset_cmd "list_after_create4" list
run_fileset_cmd "show_after_create4" show myfileset4
run_session_cmd "set_two_and_extra" set --filesets "myfileset2,myfileset4" --extra "myextrafileset1"
run_session_cmd "show_after_two_and_extra" show
run_fileset_cmd "fileset2_ro" ro myfileset2
run_fileset_cmd "list_after_2_ro" list
run_fileset_cmd "show_2_after_2_ro" show myfileset2
run_session_cmd "show_after_2_ro" show
run_file_cmd "add_x5" add x/5.txt
run_fileset_cmd "show_2_after_add_x5" show myfileset2
run_fileset_cmd "show_3_after_add_x5" show myfileset3
run_fileset_cmd "show_e1_after_add_x5" show myextrafileset1
run_fileset_cmd "show_4_after_add_x5" show myfileset4
run_session_cmd "show_after_add_x5" show
run_session_cmd "content_after_add_x5" content
#
export MAIA_SESSION=bar
run_session_cmd "show_after_use_bar" show
# Test 5: show current session info
run_session_cmd "show_current" show

# Test 6: delete session 'foo' (should succeed if not active)
# Since 'foo' is active, first unuse it
unset MAIA_SESSION
# Now delete 'foo'
run_session_cmd "delete_foo" delete foo

# Test session copy with files
# First with normal session set
run_session_cmd "create_zoo" create zoo --workspace ws
export MAIA_SESSION=zoo
run_session_cmd "show_after_zoo" show zoo
run_file_cmd "add_file_x1" add x/1.txt
run_session_cmd "show_after_zoox1" show zoo
run_session_cmd "create_boonr" create boonr zoo
run_session_cmd "show_after_boonr" show boonr
# And then when the orig session is in resolved mode
export MAIA_SESSION=zoo
run_session_cmd "set_zoo_resolve" set --resolve
run_session_cmd "create_boore" create boore zoo
run_session_cmd "show_after_boore" show boore
# And then with no session and empty
unset MAIA_SESSION
# No workspace set
run_session_cmd "create_ee" create ee
run_session_cmd "show_after_ee" show ee
run_session_cmd "create_dup_ee" create dupee ee
run_session_cmd "show_after_dup_ee" show dupee

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
