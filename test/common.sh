# Common helper functions for MAIA CLI tests
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

# Base directories - assume test/ is current directory when running scripts
readonly TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SUITENAME=$(basename "$0" | sed 's/test_//;s/\.sh$//;')
readonly OUTPUT_DIR="$TEST_ROOT/$SUITENAME/output"
readonly EXPECTED_DIR="$TEST_ROOT/$SUITENAME/expected"
MAIA=$(realpath "$TEST_ROOT/../bin/maia")

# Unset known MAIA variables
unset MAIA_SESSION
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset OPENAI_API_KEY
unset EDITOR
unset MOCK_CURL_RESPONSE_FILE
unset CAPTURE_FILE
unset CAPTURE_HEADERS_FILE
unset MOCK_CURL_RESPONSE_FILE

# Control flags (can be overridden via env or command line)
KEEP_OUTPUT="${KEEP_OUTPUT:-false}"
REGENERATE="${REGENERATE:-false}"
DRYRUN="${DRYRUN:-false}"
VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"

# Utility: Remove a file if it exists and is empty
remove_if_empty() {
    local file="$1"
    if [[ -f "$file" && ! -s "$file" ]]; then
        rm -f "$file"
    fi
}

# Create and clean output directory before tests run
common_setup_output_dir() {
    if [[ -d "$OUTPUT_DIR" && "$KEEP_OUTPUT" != "true" ]]; then
        rm -rf "$OUTPUT_DIR"
    fi
    mkdir -p "$OUTPUT_DIR"
    if [[ "$REGENERATE" == "true" ]]; then
	if [[ -d "$EXPECTED_DIR" ]]; then
	    rm -Rf "$EXPECTED_DIR"
	fi
        mkdir -p "$EXPECTED_DIR"
    fi
}

# Optionally clean output directory after tests
common_cleanup_output_dir() {
    if [[ "$KEEP_OUTPUT" != "true" ]]; then
        rm -rf "$OUTPUT_DIR"
    fi
}

verbose_header() {
    local testname="$1"
    local cmd="$2"
    local code="$3"
    if [[ "$VERBOSE" == "cmdmode" ]] ; then
        echo "# $cmd"
    else
        echo "-----------------------------------"
        echo "Test:      $testname"
        echo "Command:   $cmd"
    fi
    if [[ $code != 0 ]] ; then
        echo "Exit code: $code"
    fi
    if [[ "$VERBOSE" != "cmdmode" ]] ; then
        echo "-----------------------------------"
    fi
}

verbose_output() {
    local tag="$1" file="$2"
    if [[ "$VERBOSE" != "false" && -f "$file" ]]; then
        while IFS= read -r line; do
            echo "$tag $line"
        done < "$file"
    fi
}

# Setup mock curl environment to intercept API calls
setup_mock_curl() {
    # Prepend TEST_ROOT to PATH so mock curl is used
    export PATH="$TEST_ROOT:$PATH"
}

cleanup_mock_curl() {
    unset CAPTURE_FILE
    unset CAPTURE_HEADERS_FILE
    unset MOCK_CURL_RESPONSE_FILE
}

normalize_output() {
    sed "s|$XMAIA_HOME|<MAIA_HOME>|g;s/20[0-9][0-9][0-2][0-9][0-3][0-9]T[0-2][0-9][0-5][0-9][0-5][0-9]/<dateandtime>/g;"
}

normalize_headers() {
    sed 's/\/[0-9][0-9]*\//\/<date>/g;s/X-Amz-Date: .*/X-Amz-Date: <dateandtime>/g;s/Signature=.*/Signature=<signature>/g;'
}


# Run a command, capturing stdout, stderr, and exit code
# Arguments:
#   $1 - test name (e.g. "workspace_list")
#   $2... - command and args
# Produces files under OUTPUT_DIR:
#   $OUTPUT_DIR/${testname}.out  (stdout)
#   $OUTPUT_DIR/${testname}.err  (stderr)
#   $OUTPUT_DIR/${testname}.exit (only if exit code != 0)
# Returns exit code of command
run_cmd() {
    local testname="$1"
    shift
    local cmd=( "$@" )

    local raw_out=$(mktemp)
    local raw_err=$(mktemp)

    # Run command, capture raw outputs
    "${cmd[@]}" > "$raw_out" 2> "$raw_err"
    local exit_code=$?

    # Normalize outputs before saving
    normalize_output < "$raw_out" > "$OUTPUT_DIR/${testname}.out"
    normalize_output < "$raw_err" > "$OUTPUT_DIR/${testname}.err"

    # Remove empty normalized output files
    remove_if_empty "$OUTPUT_DIR/${testname}.request.json"
    remove_if_empty "$OUTPUT_DIR/${testname}.headers.txt"
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

# Compare actual output files with expected files
# Arguments:
#   $1 - test name (e.g. "workspace_list")
#   $2 - output extension ("out" or "err")
# Returns 0 if match, non-zero if differs
compare_output() {
    local testname="$1"
    local ext="$2"

    local actual="$OUTPUT_DIR/${testname}.${ext}"
    local expected="$EXPECTED_DIR/${testname}.${ext}"

    # If expected file missing and actual file exists and is empty, treat as match
    if [[ ! -f "$expected" ]]; then
        if [[ ! -f "$actual" || ! -s "$actual" ]]; then
            # Both missing or actual empty, treat as match
            return 0
        else
            echo "Expected file missing: $expected. Now contains:"
	    cat "$actual"
            return 1
        fi
    fi

    # If actual file missing and expected empty, treat as match
    if [[ ! -f "$actual" ]]; then
        if [[ ! -s "$expected" ]]; then
            return 0
        else
            echo "Actual output missing: $actual. Expected:"
	    cat "$expected"
            return 1
        fi
    fi

    # Files are normalized on save, so compare directly
    if ! diff -u "$expected" "$actual" >/dev/null 2>&1; then
        echo "Output mismatch for $testname.$ext:"
        diff -u "$expected" "$actual" || true
        return 1
    fi
    return 0
}

# Compare exit codes if stored
# Arguments:
#   $1 - test name
compare_exit_code() {
    local testname="$1"

    local actual_exit="$OUTPUT_DIR/${testname}.exit"
    local expected_exit="$EXPECTED_DIR/${testname}.exit"

    if [[ -f "$expected_exit" ]]; then
        if [[ ! -f "$actual_exit" ]]; then
            echo "Exit code expected but command returned 0"
            return 1
        fi
        if ! diff -q "$expected_exit" "$actual_exit" >/dev/null 2>&1; then
            echo "Exit code mismatch for $testname:"
            diff -u "$expected_exit" "$actual_exit" || true
            return 1
        fi
    else
        # No expected exit code means expect success (0)
        if [[ -f "$actual_exit" ]]; then
            echo "Unexpected non-zero exit code for $testname:"
            cat "$actual_exit"
            return 1
        fi
    fi
    return 0
}

# Run a command, compare outputs and exit code, and report results
# Arguments:
#   $1 - test name (e.g. "workspace_list")
#   $2... - command and args
run_and_check() {
    local testname="$1"
    shift

    export CAPTURE_FILE="$OUTPUT_DIR/${testname}.request.json"
    export CAPTURE_HEADERS_FILE="$OUTPUT_DIR/${testname}.headers.txt"
    local exit_code=$(run_cmd "$testname" "$@")
    # If we have headers, normalize it
    if [[ -s "$OUTPUT_DIR/${testname}.headers.txt" ]]; then
	mv "$OUTPUT_DIR/${testname}.headers.txt" "$OUTPUT_DIR/${testname}.headers.txt.x"
	cat "$OUTPUT_DIR/${testname}.headers.txt.x" | normalize_headers > "$OUTPUT_DIR/${testname}.headers.txt"
	rm -f "$OUTPUT_DIR/${testname}.headers.txt.x"
    fi
    
    local ok=0

    if [[ "$REGENERATE" == "true" ]]; then
        # Expected files are normalized output from run_cmd
	for E in out err exit request.json headers.txt ; do
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
        compare_output "$testname" "request.json" || ok=1
        compare_output "$testname" "headers.txt" || ok=1
        compare_exit_code "$testname" || ok=1
    fi

    # Print verbose output if requested
    if [[ "$VERBOSE" != "false" ]]; then
        verbose_header "$testname" "$*" "$exit_code"
        verbose_output ">" "$OUTPUT_DIR/${testname}.err"
        [[ -f "$OUTPUT_DIR/${testname}.out" ]] && cat "$OUTPUT_DIR/${testname}.out"
        verbose_output "H" "$OUTPUT_DIR/${testname}.headers.txt"
        verbose_output "R" "$OUTPUT_DIR/${testname}.request.json"
    fi

    if [[ "$DRYRUN" == "false" ]] ; then
	if [[ $ok -ne 0 ]]; then
            echo "Test '$testname' failed output or exit code comparison."
            return 1
	fi
    fi

    return 0
}

# Helper: encode plain text AI response into JSON assistant response format
encode_response_to_json() {
    local input_file="$1"
    local output_file="$2"
    local content=$(jq -R -s '.' < "$input_file")
    cat > "$output_file" <<EOF
{
  "id": "mock-response-id",
  "object": "chat.completion",
  "created": 1234567890,
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": $content
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 5,
    "total_tokens": 15
  }
}
EOF
}

# Setup isolated MAIA_HOME directory for tests
# Creates a temp directory, cds into it, runs 'maia home create'
# Sets MAIA_HOME env variable for child processes
setup_maia_home() {
    export SAVEDIR=`pwd`
    local tmpdir=$(mktemp -d -t maia_test_XXXXXX)
    cd "$tmpdir"
    $MAIA home create > /dev/null 2>&1
    export XMAIA_HOME="$tmpdir"
    if [[ "$DEBUG" == "true" ]] ; then
	$MAIA config term_loglevel "DEBUG" > /dev/null 2>&1
    else
	$MAIA config term_loglevel "NOTICE" > /dev/null 2>&1
    fi
}

# Cleanup MAIA_HOME temp directory created by setup_maia_home
cleanup_maia_home() {
    if [[ -n "${XMAIA_HOME:-}" && -d "$XMAIA_HOME" ]]; then
	cd "$SAVEDIR"
        rm -rf "$XMAIA_HOME"
    fi
}

# Print test header for clarity
test_header() {
    echo "=== Running test: $1 ==="
}

# Print test footer for clarity
test_footer() {
    echo "=== Test finished: $1 ==="
}

# Fail test with message and exit non-zero
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

test_start() {
    echo "Running $SUITENAME tests..."
}

# Print end message for test script based on SUITENAME derived from filename
test_end() {
    echo "${SUITENAME^} tests completed."
}
