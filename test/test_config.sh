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

run_config_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_config_${test_id}" $MAIA config "$@"
}

# Test help output
run_config_cmd "help" --help

# Test list config keys
run_config_cmd "list" list

# Test list all config keys
run_config_cmd "list_all" --all list

# Test list cost related config keys
run_config_cmd "list_cost" --cost list

# Test list file related config keys
run_config_cmd "list_file" --file list

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset OPENAI_API_KEY
# Test show config (no args)
run_config_cmd "show" 

export AWS_ACCESS_KEY_ID="dummy1"
export AWS_SECRET_ACCESS_KEY="dummy2"
export AWS_SESSION_TOKEN="dummy3"
export OPENAI_API_KEY="dummy4"
# Test show config (no args)
run_config_cmd "show_env"

# Test show config (no args)
run_config_cmd "show_all" --all

# Test show config (no args)
run_config_cmd "show_cost" --cost

# Test show config (no args)
run_config_cmd "show_file" --file

# Test get all config keys (default)
run_config_cmd "get_all" get
run_config_cmd "impl_get_all"

# Test get a specific key
run_config_cmd "get_key" get model

# Test get config keys with scope filter
run_config_cmd "get_scope_home" --scope home get

# Test set a config key (default scope: home)
run_config_cmd "set_key" set temperature 0.5

# Test get after set (should reflect new value)
run_config_cmd "get_temperature" get temperature

# Test unset a config key (default scope: home)
run_config_cmd "unset_key" unset temperature

# Test get after unset (should revert to default or lower scope)
run_config_cmd "get_temperature_after_unset" get temperature

# Test set a config key with explicit scope
run_config_cmd "set_key_user" --scope user set temperature 0.7

# Test get with explicit scope user
run_config_cmd "get_key_user" --scope user get temperature

# Test unset with explicit scope user
run_config_cmd "unset_key_user" --scope user unset temperature

# Test default behavior: no command with name and value sets, with name only gets
run_config_cmd "default_set" temperature 0.3
run_config_cmd "show_after_set"
run_config_cmd "default_get" temperature

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
