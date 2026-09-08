#!/usr/bin/env bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
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

# Helper to run a session command and check output
run_tool_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_tool_${test_id}" $MAIA tool "$@"
}

# Helper to run a skill command and check output
run_change_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_change_${test_id}" $MAIA change "$@"
}

capture_change() {
    cat "${TEST_ROOT}/tool_change/output/test_tool_${1}.capture" | grep -A1 "Change proposal created:" | grep "^2"
}

text1='# Some header\n'
text2='\tTab indented text\n'
text2var='    Tab indented text \n'
text3='\tMore tab indented text \n'
text3var='\tMore tab indented text\n'
text4='# Some other header\n'
new2="\t\tNew tab indented text\n"
mkdir 1
printf '%b' "$text1$text2$text3$text4$text2var$text3var" > 1/12342v3v.txt
printf '%b' "$text1$text2$text3$text4" > 1/1234.txt

# First an error case when there is no workspace
run_tool_cmd "file-change_err_1" run file-change "{\"path\":\"1/12342v3v.txt\",\"changes\":[{\"existing\":\"$text2\",\"replacement\":\"$new2\"}]}"

# Then we create the workspace so we have something to work on
$MAIA workspace create default --path "$XMAIA_HOME" > /dev/null 2>&1
$MAIA session create testsess --workspace default > /dev/null 2>&1
export MAIA_SESSION=testsess
run_tool_cmd "append" replace "file-*" "change-*"

# Now to the real tests

# Simple success cases
run_tool_cmd "file-change_1234_2" run file-change "{\"path\":\"1/1234.txt\",\"changes\":[{\"existing\":\"$text2\",\"replacement\":\"$new2\"}]}"
run_tool_cmd "file-change_1234_3" run file-change "{\"path\":\"1/1234.txt\",\"changes\":[{\"existing\":\"$text3\",\"replacement\":\"$new2\"}]}"
C1=$(capture_change "file-change_1234_3")
run_change_cmd "manual-apply-1234_3" apply "$C1"
run_change_cmd "manual-revert-1234_3" revert "$C1"

run_tool_cmd "file-change_12342v3v_2" run file-change "{\"path\":\"1/12342v3v.txt\",\"changes\":[{\"existing\":\"$text2\",\"replacement\":\"$new2\"}]}"
run_tool_cmd "file-change_12342v3v_3" run file-change "{\"path\":\"1/12342v3v.txt\",\"changes\":[{\"existing\":\"$text3\",\"replacement\":\"$new2\"}]}"
run_tool_cmd "file-change_12342v3v_2v" run file-change "{\"path\":\"1/12342v3v.txt\",\"changes\":[{\"existing\":\"$text2var\",\"replacement\":\"$new2\"}]}"

# Now to the problematic cases when we have indentation change

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
