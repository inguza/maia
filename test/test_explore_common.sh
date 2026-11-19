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
source "$(dirname "$0")/../lib/maia/core/explore-common.sh"

test_start

common_setup_output_dir
setup_maia_home

test_tmp_dir="$(mktemp -d)"
index_file="$test_tmp_dir/exploreset.txt"
run_view_index_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_view_${test_id}" cat "$index_file"
    run_and_check "test_render_${test_id}" explore_render_index "$index_file"
}

# Normalization
#assert_equals "/" "/" "$(explore_normalize_dir_path "/")"
#assert_equals "." "/" "$(explore_normalize_dir_path ".")"
#assert_equals "a" "a/" "$(explore_normalize_dir_path "a")"

# Create a dir structure to explore (creation out of order to check sorting)
mkdir -p a/b/c/d
mkdir -p a/d/d
touch a/3.txt
touch a/1.txt
touch a/2.txt
touch a/4.txt
touch 2.txt
touch 3.txt
touch 1.txt

explore_path "$index_file" "." 50 1 1000 a/1.txt
run_view_index_cmd "explore_a_1_txt"

# Check that a re-visit update parents too
touch 5.txt
touch a/5.txt

explore_clear_visit_cache
explore_path "$index_file" "." 50 1 1000 a/1.txt
run_view_index_cmd "explore_a_1_txt_revisit"

# Reset to test the explorey
: > "$index_file"
explore_clear_visit_cache
explore_path "$index_file" "." 50 1 1000 a/b/c/d
run_view_index_cmd "explore_a_b_c_d_txt"

# Reset to test the explorey
: > "$index_file"
explore_clear_visit_cache
explore_path "$index_file" "." 50 1 1000 "/"
run_view_index_cmd "explore_root_max_50_1"

# Reset to test the explorey
: > "$index_file"
explore_clear_visit_cache
explore_path "$index_file" "." 3 1 1000 "/"
run_view_index_cmd "explore_root_max_3_1"

# Reset to test the explorey
: > "$index_file"
explore_clear_visit_cache
explore_path "$index_file" "." 8 3 1000 "/"
run_view_index_cmd "explore_root_max_8_3"

# A cumulative budget includes all records, including the root seed.
: > "$index_file"
explore_clear_visit_cache
explore_path "$index_file" "." 20 1 2 "/"
run_view_index_cmd "root_cumulative_budget_2"

# Stale entries are pruned before the budget is calculated, freeing capacity.
rm -f 1.txt
touch 0.txt
explore_clear_visit_cache
explore_path "$index_file" "." 1 1 2 "/"
run_view_index_cmd "root_prune_stale_before_budget"

# Explicitly supplied paths are always indexed, even when they exceed both budgets.
: > "$index_file"
explore_clear_visit_cache
explore_path "$index_file" "." 0 0 0 a/1.txt 3.txt
run_view_index_cmd "explicit_paths_ignore_budgets"

# Cleanup
rm -rf -- "$test_tmp_dir"
cleanup_maia_home
common_cleanup_output_dir

test_end
