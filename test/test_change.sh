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

run_change_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_change_${test_id}" $MAIA change "$@"
}

# Test help output (short and long)
run_change_cmd "help_short" -h
run_change_cmd "help_long" --help

# Test show on empty outbox (should handle gracefully)
run_change_cmd "list_empty" list

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
