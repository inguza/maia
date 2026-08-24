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
export MAIA_SESSION=default
cd $XMAIA_HOME

run_shell_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_shell_${test_id}" $MAIA shell "$@"
}

# Test help output (short and long)
run_shell_cmd "help_short" -h
run_shell_cmd "help_long" --help


# Setup shells directory with mock data

run_shell_cmd "list_empty" list

echo "echo 'Foo'" | run_shell_cmd "int_0"

# Additional tests for shell management
show_x() {
    local x="$1"
    run_shell_cmd "list_after_$x" create
}

# Test applied command
run_shell_cmd "create" create
show_x create

run_shell_cmd "create_x" create x
show_x create_x

echo "echo 'Foo a'" | run_shell_cmd "enter_d" enter
show_x run

echo "echo 'Foo x'" | run_shell_cmd "enter_x" enter x
show_x run_x

# Test delete command
run_shell_cmd "delete" delete
show_x delete

run_shell_cmd "delete_x" delete x
show_x delete_x

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
