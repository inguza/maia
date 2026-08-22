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
$MAIA workspace create default --use --path "$XMAIA_HOME" > /dev/null 2>&1
$MAIA session create default > /dev/null 2>&1
# Allow all tools
$MAIA tool replace "*" > /dev/null 2>&1
touch "$XMAIA_HOME/file-to-see.txt"
#
TOOL_DIR="$(realpath "$TEST_ROOT/../lib/maia/tools")"
TMP_ARGS_FILE=$(mktemp)
# Environment setup for tool running
export AIA_ROOT="$(realpath "$TEST_ROOT/..")"
export MAIA_SESSION=default
export MAIA_BIN="$MAIA"
export MAIA_CORE_LIB_DIR="$(realpath "$TEST_ROOT/../lib/maia/core")"
export MAIA_TOOLS_LIB_DIR="$TOOL_DIR"
export TERM_LOGLEVEL=NOTICE

capture_change() {
    cat "${TEST_ROOT}/various_tools/output/test_tool_${1}.capture" | grep -A1 "Change proposal created:" | grep "^2"
}

run_maia_tool_cmd() {
    local testname="$1"
    shift
    local tool_cmd="$1"
    shift
    local tool_args="$1"
    shift
    local raw_out=$(mktemp)
    local raw_err=$(mktemp)

    cd "$XMAIA_HOME"
    echo "$tool_args" > "$TMP_ARGS_FILE"
    echo "Running "$TOOL_DIR"/$tool_cmd($tool_args)"
    echo '' | "$TOOL_DIR"/$tool_cmd "$@" 3<$"$TMP_ARGS_FILE" > "$raw_out" 2> "$raw_err"
    local exit_code=$?

    # Normalize outputs before saving
    cat "$raw_out" "$raw_err" > "$OUTPUT_DIR/${testname}.capture"
    normalize_output < "$raw_out" > "$OUTPUT_DIR/${testname}.out"
    normalize_output < "$raw_err" > "$OUTPUT_DIR/${testname}.err"

    # Remove empty normalized output files
    remove_if_empty "$OUTPUT_DIR/${testname}.out"
    remove_if_empty "$OUTPUT_DIR/${testname}.err"
    
    # Clean up temporary raw files
    rm -f "$raw_out" "$raw_err"
    # Save exit code only if non-zero
    local exit_file="$OUTPUT_DIR/${testname}.exit"
    if [[ $exit_code -ne 0 ]]; then
        echo "$exit_code" > "$exit_file"
    else
        rm -f "$exit_file"
    fi

    echo "$exit_code"
}

run_maia_tool_and_check() {
    local testname="$1"
    shift
    local exit_code=$(run_maia_tool_cmd "$testname" "$@")
    
    local ok=0
    if [[ "$REGENERATE" == "true" ]]; then
        # Expected files are normalized output from run_cmd
	for E in out err exit ; do
	    if [[ -e "$EXPECTED_DIR/${testname}.$E" ]]; then
		echo "$EXPECTED_DIR/${testname}.$E already exists. Duplicate test definition."
		exit 1
	    fi
            cp "$OUTPUT_DIR/${testname}.$E" "$EXPECTED_DIR/${testname}.$E" 2>/dev/null || true
	done
        echo "Regenerated expected outputs and exit code for $testname"
    elif [[ "$DRYRUN" == "false" ]] ; then
        compare_output "$testname" "out" || ok=1
        compare_output "$testname" "err" || ok=1
        compare_exit_code "$testname" || ok=1
    fi

    # Print verbose output if requested
    if [[ "$VERBOSE" != "false" ]]; then
        verbose_header "$testname" "$*" "$exit_code"
        verbose_output ">" "$OUTPUT_DIR/${testname}.err"
        [[ -f "$OUTPUT_DIR/${testname}.out" ]] && cat "$OUTPUT_DIR/${testname}.out"
    fi

    if [[ "$DRYRUN" == "false" ]] ; then
	if [[ $ok -ne 0 ]]; then
            echo "Test '$testname' failed output or exit code comparison."
            return 1
	fi
    fi

    return 0
}

run_tool_cmd() {
    local test_id="$1"
    shift
    run_maia_tool_and_check "test_tool_${test_id}" "$@"
}

##### DEBUG
##### basic tools

##### Pipe
# Pipe with unknown
run_tool_cmd "pipe-to-unknown-1" "pipe.sh" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"unknown","arguments":{"content":"searchpattern"}}
]}'

# Pipe ls
# We do not test with ls -l because that generate a new timestamp each run
run_tool_cmd "pipe-ls-1" "pipe.sh" '{"pipeline":[
{"name":"util-ls","arguments":{"pathspec":".","arguments":""}}
]}'

# Pipe ls to grep
# We do not test with ls -l because that generate a new timestamp each run
run_tool_cmd "pipe-ls-to-grep-1" "pipe.sh" '{"pipeline":[
{"name":"util-ls","arguments":{"pathspec":".","arguments":[]}},
{"name":"util-grep","arguments":{"searchpattern":"file"}}
]}'

# Pipe to grep
run_tool_cmd "pipe-to-grep-1" "pipe.sh" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"util-grep","arguments":{"searchpattern":"Test"}}
]}'
run_tool_cmd "pipe-to-grep-2-v" "pipe.sh" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test\n"}},
{"name":"util-grep","arguments":{"searchpattern":"Test","arguments":["-v"]}}
]}'
run_tool_cmd "pipe-to-grep-2-v-wrong" "pipe.sh" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test\n"}},
{"name":"util-grep","arguments":{"searchpattern":"Test","arguments":"-v"}}
]}'
# Pipe to tail
run_tool_cmd "pipe-to-tail-1" "pipe.sh" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"util-tail","arguments":{}}
]}'
run_tool_cmd "pipe-to-head-1" "pipe.sh" '{"pipeline":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"util-head","arguments":{}}
]}'
##### Sequence
# We can't test with ls -l because it generates a new timestamp each time
run_tool_cmd "sequence-print-ls-find" "sequence.sh" '{"sequence":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"util-ls","arguments":{"pathspec":".","arguments":""}},
{"name":"util-find","arguments":{"pathspec":"."}}
]}'
run_tool_cmd "sequence-with-unknown-1" "sequence.sh" '{"sequence":[
{"name":"core-print","arguments":{"content":"Test"}},
{"name":"unknown","arguments":{"content":"searchpattern"}}
]}'

run_tool_cmd "sequence-complicated-1" "sequence.sh" '{"sequence":[{"name":"subsession-create","arguments":{"name":"review-xcommon"}},{"name":"context-file-remember","arguments":{"filepattern":"x/x.info.yml","subsession":"review-xcommon"}},{"name":"context-file-remember","arguments":{"filepattern":"xcommon/tests/src/Functional/TestBase.php","subsession":"review-xcommon"}},{"name":"subsession-send","arguments":{"subsession":"review-xcommon","content":"Sub-session name: review-xcommon\n\nScope:\n- You are to perform an AI-only static code review of the module xcommon.\n- If you are uncertain whether a code path is exploitable at runtime (e.g., a route’s access depends on configuration), mark the item with \"note: needs confirm\" but still include full evidence and an explanation in 1–2 lines why confirmation is needed.\n- If the fault depends on external configuration, still include it but mark severity conservatively.\n- Do not run grep or automated pattern matching tools. Read the loaded files and use your reasoning.\n- If you find zero faults, return exactly: \"No faults found.\" and include the list of files you examined.\n\nOutput format (exact expected Markdown)\nFor each fault produce:\n\n- module: xcommon\n- file: relative/path/to/file.php\n- lines: <start>-<end>\n- issue_type: <RCE|XSS|SQLi|CSRF|Syntax|Schema|DataLoss|Logic|Other>\n- severity: <Critical|High|Medium|Low>\n- concise_description: One-line description (no more than 120 chars)\n- evidence:\n  <show exact code lines with line numbers, e.g. \"123:    $x = $_GET['p'];\"> \n- reproduction_steps: (optional, 1–3 short steps)\n- note: (optional, single sentence if needs_confirm)\n\nOnly list faults. No other text or commentary. End output.\n\nToken & subsession constraints:\n- Keep the total memory within 100k tokens. If needed, request to the coordinator to split the module further.\n- After producing the report, run context-file-forget for all files loaded in this sub-session and exit.\n\nProceed to review now."}}]}'

##### Print
run_tool_cmd "print-1" "print.sh" '{"content":"This is a test\nAnd after new line\n"}'

##### GNU
run_tool_cmd "grep-complicated-1" "grep.sh" '{"searchpattern":"unserialize\\(|eval\\(|create_function\\(|shell_exec\\(|exec\\(|passthru\\(|system\\(|`\\$\\(|preg_replace\\(\\s*[\"].*e.*[\"]","pathspec":"."}'

##### maia-* tools
subsession1="sub-session-1"
run_tool_cmd "maia-subsession-list-empty-1" "maia-subsession-list.sh" '{}'
run_tool_cmd "maia-subsession-create-ss1-1" "maia-subsession-create.sh" '{"name":"'$subsession1'"}'
run_tool_cmd "maia-subsession-list-ac1-1" "maia-subsession-list.sh" '{}'
run_tool_cmd "maia-subsession-show-ss1-1_acreate" "maia-subsession-show.sh" '{"name":"'$subsession1'"}'
run_tool_cmd "maia-subsession-delete-ss1-1" "maia-subsession-delete.sh" '{"name":"'$subsession1'"}'
run_tool_cmd "maia-subsession-list-ad1-1" "maia-subsession-list.sh" '{}'
run_tool_cmd "maia-subsession-show-ss1-1_adelete" "maia-subsession-show.sh" '{"name":"'$subsession1'"}'
run_tool_cmd "maia-subsession-create-ss1-2" "maia-subsession-create.sh" '{"name":"'$subsession1'"}'
run_tool_cmd "maia-subsession-list-ac2-1" "maia-subsession-list.sh" '{}'
run_tool_cmd "maia-subsession-show-ss1-2_acreate" "maia-subsession-show.sh" '{"name":"'$subsession1'"}'

run_tool_cmd "maia-file-remember-ss1-1-missing" "maia-file-remember.sh" '{"filepattern": "icommon/icommon.info.yml","subsession": "'$subsession1'"}'
run_tool_cmd "maia-file-forget-ss1-1-missing" "maia-file-forget.sh" '{"filepattern": "icommon/icommon.info.yml","subsession": "'$subsession1'"}'
mkdir -p "$XMAIA_HOME/pathx"
echo "File to remember" > "${XMAIA_HOME}/pathx/remember.txt"
run_tool_cmd "maia-file-remember-ss1-2" "maia-file-remember.sh" '{"filepattern": "pathx/remember.txt","subsession": "'$subsession1'"}'
run_tool_cmd "maia-file-forget-ss1-2" "maia-file-forget.sh" '{"filepattern": "pathx/remember.txt","subsession": "'$subsession1'"}'
# maia-send not tested
# maia-change-apply tested below in file-* tools

# file-* tools
# write
run_tool_cmd "file-write-1-1" "file-write.sh" '{"path": "x/1.txt","content":"First write content 1\n"}'
run_tool_cmd "file-write-2-1" "file-write.sh" '{"path": "pathx/2.txt","content": "First write content 2\n"}'
export ASSISTANT_BASEID="20260717T214714-68e33e97"
run_tool_cmd "file-write-1-2" "file-write.sh" '{"path": "x/1.txt","content":"Second write content 1\n"}'
C1=$(capture_change "file-write-1-2")
#export ASSISTANT_BASEID="20260817T214714-68e33e98"
run_tool_cmd "file-write-2-2" "file-write.sh" '{"path": "pathx/2.txt","content": "First write content 2\nSecond write\n"}'
C2=$(capture_change "file-write-2-2")
run_tool_cmd "maia-change-apply-1" "maia-change-apply.sh" '{"id": ["'$C1'"]}'
run_tool_cmd "maia-change-apply-2" "maia-change-apply.sh" '{"id": ["'$C1'","'$C2'"]}'
run_tool_cmd "maia-change-apply-3" "maia-change-apply.sh" '{"id": []}'
# Not existing
run_tool_cmd "maia-change-apply-err" "maia-change-apply.sh" '{"id": ["20260817T214714-68e33e97-3"]}'
# Out of path
run_tool_cmd "file-write-3-1" "file-write.sh" '{"path": "../x/1.txt","content":"First write content 1"}'
run_tool_cmd "file-write-4-1" "file-write.sh" '{"path": "/../x/1.txt","content":"First write content 1"}'
run_tool_cmd "file-write-5-1" "file-write.sh" '{"path": "~/1.txt","content":"First write content 1"}'
run_tool_cmd "file-write-6-1" "file-write.sh" '{"path": "x/../../1.txt","content":"First write content 1"}'

# Append
run_tool_cmd "file-append-1-3" "file-append.sh" '{"path": "x/1.txt","content":"Append it 1\n"}'
#export ASSISTANT_BASEID="20260817T214714-68e33e99"
run_tool_cmd "file-change-1-3" "file-change.sh" '{"path": "x/1.txt","changes":[{"old":"Second write content 1\n","new":"Rewritten content 1\n"}]}'
C3=$(capture_change "file-change-1-3")
run_tool_cmd "maia-change-apply-4" "maia-change-apply.sh" '{"id": ["'$C3'"]}'

# Curl
run_tool_cmd "curl-1" "curl.sh" '{"url": "https://inguza.org/testharness/maia/will-not-change.html"}'

# Job management
run_tool_cmd "job-start" "job-start.sh" '{"name":"util-ls","arguments":{"pathspec":".","arguments":[]}}'
run_tool_cmd "job-list" "job-list.sh" '{}'
ID=$($MAIA job list)
run_tool_cmd "job-show" "job-id.sh show" '{"id":"'$ID'"}'
run_tool_cmd "job-status" "job-id.sh status" '{"id":"'$ID'"}'
run_tool_cmd "job-output" "job-id.sh output" '{"id":"'$ID'"}'
run_tool_cmd "job-canel" "job-id.sh cancel" '{"id":"'$ID'"}'
run_tool_cmd "job-delete" "job-id.sh delete" '{"id":"'$ID'"}'
run_tool_cmd "job-exist" "job-id.sh exist" '{"id":"'$ID'"}'

# Lynx
# not tested

# Pandoc
# pandoc not tested

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
