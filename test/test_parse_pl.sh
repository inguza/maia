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

DEBUGARG="";
if [[ "$DEBUG" == "true" ]] ; then
    DEBUGARG=" --loglevel DEBUG "
fi

common_setup_output_dir
setup_maia_home

PARSE=$(realpath "$TEST_ROOT/../lib/maia/core/parse.pl")

run_parse_pl_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_parse_pl_${test_id}" $PARSE parse $DEBUGARG "$@"
}

run_test_no() {
    mkdir test_$1_i
    mkdir test_$1_ws
    cp $TEST_ROOT/parse_pl/input/test$1.txt test_$1_i
    cp $TEST_ROOT/parse_pl/match/test$1*.*[a-z] test_$1_ws 2>/dev/null || true
    run_parse_pl_cmd "test_$1_parse" test_$1_i/test$1.txt `pwd`/test_$1_ws
    run_and_check "test_$1_output" cat test_$1_i/test$1.txt
    for FPATH in test_$1_i/*pending*.*; do
	F=$(basename "$FPATH")
	run_and_check "test_$1_parsed_$F" cat test_$1_i/$F
    done
    rm -Rf test_$1
}

TESTS=$*
if [[ -z "$TESTS" ]] ; then
    TESTS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 d1 d2 d3 d4 d5 d6 d7"
fi
for I in $TESTS ; do
    run_test_no $I
done

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
