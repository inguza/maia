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

run_home_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_home_${test_id}" $MAIA home "$@"
}

# Test help output
run_home_cmd "help" --help

# Test show current home (should output path)
run_home_cmd "show" 

# Test create a new home in a temp directory
tmpdir=$(mktemp -d -t maia_home_test_XXXXXX)
run_home_cmd "create_tmp" create "$tmpdir"

# Test delete the created home
run_home_cmd "delete_tmp" delete "$tmpdir"

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
