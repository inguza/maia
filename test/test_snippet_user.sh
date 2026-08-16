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

common_setup_output_dir
setup_maia_home

run_user_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_user_${test_id}" $MAIA user "$@"
}

run_snippet_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_snippet_${test_id}" $MAIA snippet "$@"
}

# Test list snippets (likely empty initially)
run_snippet_cmd "list" list

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
