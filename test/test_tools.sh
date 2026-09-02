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

# Test 0: The help
run_tools_cmd "help" --help

run_tools_cmd "list" list
run_tools_cmd "show_empty" show
run_tools_cmd "scope_empty" --scope
run_tools_cmd "refresh_empty" refresh
run_tools_cmd "verify_empty" verify

run_tools_cmd "append" append "core-pipe"
run_tools_cmd "list_after_append_pipe" list
run_tools_cmd "show_after_append_pipe" show
run_tools_cmd "scope_after_append_pipe" --scope
run_tools_cmd "refresh_after_append_pipe" refresh
run_tools_cmd "verify_after_append_pipe" verify

run_tools_cmd "enable" enable "core-sequence"
run_tools_cmd "list_after_enable_seq" list
run_tools_cmd "show_after_enable_seq" show
run_tools_cmd "scope_after_enable_seq" --scope
run_tools_cmd "refresh_after_enable_seq" refresh
run_tools_cmd "verify_after_enable_seq" verify

run_tools_cmd "allow" allow "core-print"
run_tools_cmd "list_after_allow_print" list
run_tools_cmd "show_after_allow_print" show
run_tools_cmd "scope_after_allow_print" --scope
run_tools_cmd "refresh_after_allow_print" refresh
run_tools_cmd "verify_after_allow_print" verify

run_tools_cmd "run1" run core-print '{"content":"Test\n"}'
run_tools_cmd "run-err" run core-print-notexisting '{"content":"Test\n"}'

run_tools_cmd "replace" replace "net-request*"
run_tools_cmd "list_after_replace_mul" list
run_tools_cmd "show_after_replace_mul" show
run_tools_cmd "scope_after_replace_mul" --scope
run_tools_cmd "refresh_after_replace_mul" refresh
run_tools_cmd "verify_after_replace_mul" verify

run_tools_cmd "clear" clear
run_tools_cmd "list_after_clear" list
run_tools_cmd "show_after_clear" show
run_tools_cmd "scope_after_clear" --scope
run_tools_cmd "refresh_after_clear" refresh
run_tools_cmd "verify_after_clear" verify

run_tools_cmd "delete" delete
run_tools_cmd "list_after_delete" list
run_tools_cmd "show_after_delete" show
run_tools_cmd "scope_after_delete" --scope
run_tools_cmd "refresh_after_delete" refresh
run_tools_cmd "verify_after_delete" verify

# edit not tested

# Test tool restrict
run_tools_cmd "restrict_empty" restrict "*"
run_tools_cmd "list_after_restrict_empty" list
run_tools_cmd "show_after_restrict_empty" show
run_tools_cmd "view_after_restrict_empty" view

run_tools_cmd "allow-core-print-1" allow "core-print"
run_tools_cmd "restrict_core-print-1" restrict "d*"
run_tools_cmd "list_after_restrict_core-print-1" list
run_tools_cmd "view_after_restrict_core-print-1" view
run_tools_cmd "restrict_core-print-2" restrict "a*" "c*" "b*"
run_tools_cmd "list_after_restrict_core-print-2" list
run_tools_cmd "view_after_restrict_core-print-2" view

run_tools_cmd "allow-core-print-2" allow "core-print" "file*"
run_tools_cmd "restrict_file-write" restrict "file-write"
run_tools_cmd "list_after_restrict_file-write" list
run_tools_cmd "view_after_restrict_file-write" view

run_tools_cmd "allow_all_allow" allow "*"
run_tools_cmd "list_after_allow_all_allow" list
run_tools_cmd "show_after_allow_all_allow" show

run_tools_cmd "restrict_subsession" restrict "subsession-*"
run_tools_cmd "list_after_restrict_subsession" list
run_tools_cmd "show_after_restrict_subsession" show
run_tools_cmd "view_after_restrict_subsession" view

run_tools_cmd "restrict_exact" restrict "core-pipe"
run_tools_cmd "list_after_restrict_exact" list
run_tools_cmd "show_after_restrict_exact" show
run_tools_cmd "view_after_restrict_exact" view

# Test skill restrict
run_skills_cmd "restrict_empty" restrict "*"
run_skills_cmd "list_after_restrict_empty" list
run_skills_cmd "show_after_restrict_empty" show
run_skills_cmd "view_after_restrict_empty" view

run_skills_cmd "allow_all_1" allow "*"
run_skills_cmd "restrict_all" restrict "*"
run_skills_cmd "list_after_restrict_all" list
run_skills_cmd "show_after_restrict_all" show
run_skills_cmd "view_after_restrict_all" view

run_skills_cmd "allow_all" allow "*"
run_skills_cmd "list_after_allow_all_allow" list
run_skills_cmd "show_after_allow_all_allow" show
run_skills_cmd "view_after_allow_all_allow" view

run_skills_cmd "allow_all_2" allow "*"
run_skills_cmd "restrict_subsession" restrict "subsession"
run_skills_cmd "list_after_restrict_subsession" list
run_skills_cmd "show_after_restrict_subsession" show
run_skills_cmd "view_after_restrict_subsession" view

run_skills_cmd "allow_all_3" allow "*"
run_skills_cmd "restrict_multi_patterns" restrict "foo*" "subs*" "bar*"
run_skills_cmd "list_after_restrict_multi_patterns" list
run_skills_cmd "show_after_restrict_multi_patterns" show
run_skills_cmd "view_after_restrict_multi_patterns" view

run_skills_cmd "allow_all_4" allow "*"
run_skills_cmd "restrict_prefix" restrict "sub*"
run_skills_cmd "list_after_restrict_prefix" list
run_skills_cmd "show_after_restrict_prefix" show
run_skills_cmd "view_after_restrict_prefix" view

run_skills_cmd "allow_all_5" allow "*"
run_skills_cmd "restrict_suffix" restrict "*ession"
run_skills_cmd "list_after_restrict_suffix" list
run_skills_cmd "show_after_restrict_suffix" show
run_skills_cmd "view_after_restrict_suffix" view

run_skills_cmd "allow_all_6" allow "*"
run_skills_cmd "restrict_exact" restrict "file"
run_skills_cmd "list_after_restrict_exact" list
run_skills_cmd "show_after_restrict_exact" show

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
