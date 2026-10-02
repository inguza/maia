#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam

parsetasks() {
    tasks=()

    if [[ -n "${param[tasks]:-}" ]]; then
	if ! mapfile_from_json tasks "${param[tasks]}" ; then
            printf '[ERROR] Argument parsing error\n' >&2
            exit 1
        fi
    fi
}

action="$1"
shift

declare -a tasks=()
parsetasks

# Disable glob expansion
$MAIA_BIN task "$action" "${tasks[@]}"
