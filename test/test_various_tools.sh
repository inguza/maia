#!/usr/bin/env bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

source "$(dirname "$0")/common.sh"

test_start

DEBUGARG="";
if [[ "$DEBUG" == "true" ]] ; then
    DEBUGARG=" --loglevel DEBUG "
fi

common_setup_output_dir
setup_maia_home

# Create default workspace after MAIA home creation
echo "Working in $XMAIA_HOME"
$MAIA workspace create default --path "$XMAIA_HOME" > /dev/null 2>&1
$MAIA session create default --workspace default > /dev/null 2>&1
# Allow all tools and skills
$MAIA tool replace "*" > /dev/null 2>&1
$MAIA skill replace "file" "session"
touch "$XMAIA_HOME/file-to-see.txt"
# Environment setup for tool running
export MAIA_SESSION=default

capture_change() {
    cat "${TEST_ROOT}/various_tools/output/test_tool_${1}.capture" | grep -A1 "Change proposal created:" | grep "^2"
}

run_tool_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_tool_${test_id}" $MAIA tool run "$@"
}

# Helper to run a session command and check output
run_tools_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_tools_${test_id}" $MAIA tools "$@"
}

# Helper to run a skill command and check output
run_skills_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_skills_${test_id}" $MAIA skill "$@"
}

##### DEBUG
##### basic tools

##### Pipe
# Pipe with unknown
run_tool_cmd "pipe-to-unknown-1" "core-pipe" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"unknown","arguments":{"content":"searchpattern"}}
]}'

# Pipe ls
# We do not test with ls -l because that generate a new timestamp each run
run_tool_cmd "pipe-ls-1" "core-pipe" '{"pipeline":[
{"name":"util-ls","arguments":{"pathspecs":["."],"arguments":[]}}
]}'

# Pipe ls to grep
# We do not test with ls -l because that generate a new timestamp each run
run_tool_cmd "pipe-ls-to-grep-1" "core-pipe" '{"pipeline":[
{"name":"util-ls","arguments":{"pathspecs":["."],"arguments":[]}},
{"name":"util-grep","arguments":{"searchpattern":"file"}}
]}'

# Pipe to grep
run_tool_cmd "pipe-to-grep-1" "core-pipe" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"util-grep","arguments":{"searchpattern":"Test"}}
]}'
run_tool_cmd "pipe-to-grep-2-v" "core-pipe" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test\n"}},
{"name":"util-grep","arguments":{"searchpattern":"Test","arguments":["-v"]}}
]}'
run_tool_cmd "pipe-to-grep-2-v-wrong" "core-pipe" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test\n"}},
{"name":"util-grep","arguments":{"searchpattern":"Test","arguments":"-v"}}
]}'
# Pipe to tail
run_tool_cmd "pipe-to-tail-1" "core-pipe" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"util-tail","arguments":{}}
]}'
run_tool_cmd "pipe-to-head-1" "core-pipe" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"util-head","arguments":{}}
]}'
##### Sequence
# We can't test with ls -l because it generates a new timestamp each time
run_tool_cmd "sequence-print-ls-find" "core-sequence" '{"sequence":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"util-ls","arguments":{"pathspecs":["."],"arguments":""}},
{"name":"util-find","arguments":{"pathspecs":["."]}}
]}'
run_tool_cmd "sequence-with-unknown-1" "core-sequence" '{"sequence":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"unknown","arguments":{"content":"searchpattern"}}
]}'

run_tool_cmd "sequence-complicated-1" "core-sequence" '{"sequence":[{"name":"session-create","arguments":{"session":"review-xcommon"}},{"name":"context-file-remember","arguments":{"files":["x/x.info.yml"]}},{"name":"session-file-remember","arguments":{"files":["xcommon/tests/src/Functional/TestBase.php"],"session":"review-xcommon"}},{"name":"session-send","arguments":{"session":"review-xcommon","content":"Sub-session name: review-xcommon\n\nScope:\n- You are to perform an AI-only static code review of the module xcommon.\n- If you are uncertain whether a code path is exploitable at runtime (e.g., a route’s access depends on configuration), mark the item with \"note: needs confirm\" but still include full evidence and an explanation in 1–2 lines why confirmation is needed.\n- If the fault depends on external configuration, still include it but mark severity conservatively.\n- Do not run grep or automated pattern matching tools. Read the loaded files and use your reasoning.\n- If you find zero faults, return exactly: \"No faults found.\" and include the list of files you examined.\n\nOutput format (exact expected Markdown)\nFor each fault produce:\n\n- module: xcommon\n- file: relative/path/to/file.php\n- lines: <start>-<end>\n- issue_type: <RCE|XSS|SQLi|CSRF|Syntax|Schema|DataLoss|Logic|Other>\n- severity: <Critical|High|Medium|Low>\n- concise_description: One-line description (no more than 120 chars)\n- evidence:\n  <show exact code lines with line numbers, e.g. \"123:    $x = $_GET['p'];\"> \n- reproduction_steps: (optional, 1–3 short steps)\n- note: (optional, single sentence if needs_confirm)\n\nOnly list faults. No other text or commentary. End output.\n\nToken & session constraints:\n- Keep the total memory within 100k tokens. If needed, request to the coordinator to split the module further.\n- After producing the report, run context-file-forget for all files loaded in this sub-session and exit.\n\nProceed to review now."}}]}'

##### Print
run_tool_cmd "print-1" "core-print" '{"content":"This is a test\nAnd after new line\n"}'

##### Shell exec
export ASSISTANT_BASEID="20260717T214714-68e23e97"
run_tool_cmd "shell-exec-1" "shell-exec" '{"commands":"make\ngcc\n"}'

##### maia-* tools
$MAIA tool replace "core-*" "file-*" "util-*" > /dev/null 2>&1
$MAIA skill replace "file"
run_tools_cmd "list-parent-tools-1" list
run_tools_cmd "view-parent-tools-1" view
run_skills_cmd "list-parent-skills-1" list
run_skills_cmd "view-parent-skills-1" view

$MAIA tool allow "session-*" "context-*"
subsession1="sub-session-1"
run_tool_cmd "maia-subsession-list-empty-1" "session-list" '{}'
run_tool_cmd "maia-subsession-create-ss1-1" "session-create" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-list-ac1-1" "session-list" '{}'
run_tool_cmd "maia-subsession-show-ss1-1_acreate" "session-show" '{"session":"'$subsession1'"}'

# restrictions
run_tool_cmd "maia-subsession-tool-list-ss1-1" "session-tool-list" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-skill-list-ss1-1" "session-skill-list" '{"session":"'$subsession1'"}'

run_tool_cmd "maia-subsession-tool-restrict-ss1-1" "session-tool-restrict"  '{"session":"'$subsession1'", "restrictions": ["util-*"]}'
run_tool_cmd "maia-subsession-skill-restrict-ss1-1" "session-skill-restrict"  '{"session":"'$subsession1'", "restrictions": ["file"]}'
run_tool_cmd "maia-subsession-tool-list-ss1-2" "session-tool-list" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-skill-list-ss1-2" "session-skill-list" '{"session":"'$subsession1'"}'
run_tools_cmd "list-parent-tools-2" list
run_tools_cmd "view-parent-tools-2" view
run_skills_cmd "list-parent-skills-2" list
run_skills_cmd "view-parent-skills-2" view

run_tool_cmd "maia-subsession-tool-allow-ss1-1" "session-tool-allow"  '{"session":"'$subsession1'", "allow": ["util-cat"]}'
run_tool_cmd "maia-subsession-skill-allow-ss1-1" "session-skill-allow"  '{"session":"'$subsession1'", "allow": ["file"]}'
run_tool_cmd "maia-session-tool-list-ss1-3" "session-tool-list" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-skill-list-ss1-3" "session-skill-list" '{"session":"'$subsession1'"}'
run_tools_cmd "list-parent-tools-3" list
run_tools_cmd "view-parent-tools-3" view
run_skills_cmd "list-parent-skills-3" list
run_skills_cmd "view-parent-skills-3" view

run_tool_cmd "maia-subsession-tool-allow-ss1-2" "session-tool-allow"  '{"session":"'$subsession1'", "allow": ["session-create"]}'
run_tool_cmd "maia-subsession-skill-allow-ss1-2" "session-skill-allow"  '{"session":"'$subsession1'", "allow": ["session"]}'
run_tool_cmd "maia-subsession-tool-list-ss1-4" "session-tool-list" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-skill-list-ss1-4" "session-skill-list" '{"session":"'$subsession1'"}'
run_tools_cmd "list-parent-tools-4" list
run_tools_cmd "view-parent-tools-4" view
run_skills_cmd "list-parent-skills-4" list
run_skills_cmd "view-parent-skills-4" view

#
run_tool_cmd "maia-subsession-delete-ss1-1" "session-delete" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-list-ad1-1" "session-list" '{}'
run_tool_cmd "maia-subsession-show-ss1-1_adelete" "session-show" '{"session":"'$subsession1'"}'

run_tool_cmd "maia-subsession-create-ss1-2" "session-create" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-list-ac2-1" "session-list" '{}'
run_tool_cmd "maia-subsession-show-ss1-2_acreate" "session-show" '{"session":"'$subsession1'"}'
run_tools_cmd "list-parent-tools-6" list
run_tools_cmd "view-parent-tools-6" view
run_skills_cmd "list-parent-skills-6" list
run_skills_cmd "view-parent-skills-6" view

run_tool_cmd "maia-file-remember-ss1-1-missing" "context-file-remember" '{"files": ["icommon/icommon.info.yml"]}'
run_tool_cmd "maia-file-forget-ss1-1-missing" "context-file-forget" '{"files": ["icommon/icommon.info.yml"]}'
mkdir -p "$XMAIA_HOME/pathx"
echo "File to remember" > "${XMAIA_HOME}/pathx/remember.txt"
run_tool_cmd "maia-file-remember-ss1-2" "session-file-remember" '{"files": ["pathx/remember.txt"],"session": "'$subsession1'"}'
run_tool_cmd "maia-file-forget-ss1-2" "session-file-forget" '{"files": ["pathx/remember.txt"],"session": "'$subsession1'"}'

$MAIA session create testsession
export MAIA_SESSION=testsession
$MAIA tool replace "core-*" "file-*" "session-*" > /dev/null 2>&1
$MAIA skill replace "file"
run_tools_cmd "list-parent-tools-7" list
run_tools_cmd "view-parent-tools-7" view
run_skills_cmd "list-parent-skills-7" list
run_skills_cmd "view-parent-skills-7" view
run_tool_cmd "maia-subsession-create-ss1-3" "session-create" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-tool-list-ss1-5" "session-tool-list" '{"session":"'$subsession1'"}'
run_tool_cmd "maia-subsession-skill-list-ss1-5" "session-skill-list" '{"session":"'$subsession1'"}'
run_tools_cmd "list-parent-tools-8" list
run_tools_cmd "view-parent-tools-8" view
run_skills_cmd "list-parent-skills-8" list
run_skills_cmd "view-parent-skills-8" view

run_tool_cmd "maia-subsession-delete-ss1-3" "session-delete" '{"session":"'$subsession1'"}'
export MAIA_SESSION=default

# session-send not tested
# change-apply tested below in file-* tools
$MAIA tool allow "change-*:write"

# file-* tools
# write
run_tool_cmd "file-write-1-1" "file-write" '{"path": "x/1.txt","content":"First write content 1\n"}'
run_tool_cmd "file-write-2-1" "file-write" '{"path": "pathx/2.txt","content": "First write content 2\n"}'
export ASSISTANT_BASEID="20260717T214714-68e33e97"
run_tool_cmd "file-write-1-2" "file-write" '{"path": "x/1.txt","content":"Second write content 1\n"}'
C1=$(capture_change "file-write-1-2")
#export ASSISTANT_BASEID="20260817T214714-68e33e98"
run_tool_cmd "file-write-2-2" "file-write" '{"path": "pathx/2.txt","content": "First write content 2\nSecond write\n"}'
C2=$(capture_change "file-write-2-2")
run_tool_cmd "maia-change-apply-1" "change-apply" '{"ids": ["'$C1'"]}'
run_tool_cmd "maia-change-apply-2" "change-apply" '{"ids": ["'$C1'","'$C2'"]}'
run_tool_cmd "maia-change-apply-3" "change-apply" '{"ids": []}'
# Revert
run_tool_cmd "maia-change-revert-2" "change-revert" '{"ids": ["'$C1'","'$C2'"]}'
run_tool_cmd "maia-change-reapply-2" "change-apply" '{"ids": ["'$C1'","'$C2'"]}'
# Not existing
run_tool_cmd "maia-change-apply-err" "change-apply" '{"ids": ["20260817T214714-68e33e97-3"]}'
# Out of path
run_tool_cmd "file-write-3-1" "file-write" '{"path": "../x/1.txt","content":"First write content 1"}'
run_tool_cmd "file-write-4-1" "file-write" '{"path": "/../x/1.txt","content":"First write content 1"}'
run_tool_cmd "file-write-5-1" "file-write" '{"path": "~/1.txt","content":"First write content 1"}'
run_tool_cmd "file-write-6-1" "file-write" '{"path": "x/../../1.txt","content":"First write content 1"}'

# Append
run_tool_cmd "file-append-1-3" "file-append" '{"path": "x/1.txt","content":"Append it 1\n"}'
#export ASSISTANT_BASEID="20260817T214714-68e33e99"
run_tool_cmd "file-change-1-3" "file-change" '{"path": "x/1.txt","changes":[{"old":"Second write content 1\n","new":"Rewritten content 1\n"}]}'
C3=$(capture_change "file-change-1-3")
run_tool_cmd "maia-change-apply-4" "change-apply" '{"ids": ["'$C3'"]}'
# Skip
run_tool_cmd "maia-change-skip-2" "change-skip" '{"ids": ["'$C1'","'$C2'"]}'

# Curl
$MAIA tool allow "web-browser-curl"

run_tool_cmd "curl-1" "web-browser-curl" '{"urls": ["https://inguza.org/testharness/maia/will-not-change.html"]}'

# Job management
$MAIA tool allow "job-*"
run_tool_cmd "job-start" "job-start" '{"name":"util-ls","arguments":{"pathspecs":["."],"arguments":[]}}'
sleep 0.1
run_tool_cmd "job-list" "job-list" '{}'
ID=$($MAIA job list)
run_tool_cmd "job-show" "job-show" '{"id":"'$ID'"}'
run_tool_cmd "job-status" "job-status" '{"id":"'$ID'"}'
run_tool_cmd "job-output" "job-output" '{"id":"'$ID'"}'
run_tool_cmd "job-cancel" "job-cancel" '{"id":"'$ID'"}'
run_tool_cmd "job-delete" "job-delete" '{"id":"'$ID'"}'
run_tool_cmd "job-exist" "job-exist" '{"id":"'$ID'"}'

# Lynx
# not tested

# Pandoc
# pandoc not tested

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
