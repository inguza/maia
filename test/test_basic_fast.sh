#!/bin/bash

#!/usr/bin/env bash
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

#set -euo pipefail

source "$(dirname "$0")/common.sh"
export MAIA_CORE_LIB_DIR="$(dirname "$0")/../lib/maia/core"
source "$(dirname "$0")/../lib/maia/core/common.sh"

test_start

common_setup_output_dir
setup_maia_home

run_function() {
    local test_id="$1"
    shift
    run_and_check "test_function_${test_id}" "$@"
}

run_function "mq_get_ferr" mq_get "test" nonexisting.txt

touch 1.txt
run_function "mq_add_desc" mq_add 1.txt "description" "something here"
run_function "mq_add_m1" mq_add 1.txt "more1" "Something here" "and here"
echo "" >> 1.txt
echo " bogus:" >> 1.txt
echo "" >> 1.txt
run_function "mq_add_m2" mq_add 1.txt "more2" "Something here2" "and here2"
run_function "mq_add_m3" mq_add 1.txt "more3" "Something here3" "and here3" "  to be included: yes"
run_function "show1" cat 1.txt
run_function "showp1" mq_pretty 1.txt
run_function "showp1h" mq_pretty 1.txt description

run_function "mq_get_description" mq_get 1.txt "description"
run_function "mq_get_more1" mq_get 1.txt "more1"
run_function "mq_get_more2" mq_get 1.txt "more2"
run_function "mq_get_more3" mq_get 1.txt "more3"
run_function "mq_get_more4" mq_get 1.txt "more4"
run_function "mq_get_more4" mq_get 1.txt "bogus"

touch 2.txt
run_function "w2_description" mq_add 2.txt "description" "Version 2 is multiline" "yes it is"
run_function "w2_more2" mq_add 2.txt "more2" "Version 2 is single-line"
run_function "show2" cat 2.txt
run_function "showp2" mq_pretty 2.txt

run_function "mq_merge" mq_merge notexistingfile.txt 1.txt 2.txt

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
