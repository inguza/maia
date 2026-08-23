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

# Some special setups for job
$MAIA session create jobtest
export MAIA_HOME="jobtest"
$MAIA tools --scope session append "core-*"

# Helper to run a session command and check output
run_job_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_job_${test_id}" $MAIA job "$@"
}

# Test 0: The help
run_job_cmd "help" --help

run_job_cmd "list_empty" list

run_job_cmd "start_print" start core-print '{"content":"Hello world"}'
run_job_cmd "list_after_start" list
ID=$($MAIA job list)
run_job_cmd "show_after_start" show $ID
run_job_cmd "status_after_start" status $ID
run_job_cmd "output_after_start" output $ID
run_job_cmd "cancel_after_start" cancel $ID
run_job_cmd "delete_after_start" delete $ID

# not exist
run_job_cmd "show_err" show 123123
run_job_cmd "status_err" status 123123
run_job_cmd "output_err" output 123123
run_job_cmd "cancel_err" cancel 123123
run_job_cmd "delete_err" delete 123123

# edit not tested

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
