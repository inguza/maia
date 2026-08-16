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

run_fileset_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_fileset_${test_id}" $MAIA fileset "$@"
}

# Test help output
run_fileset_cmd "help" --help

# Test list filesets (likely empty initially)
run_fileset_cmd "list" list

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
