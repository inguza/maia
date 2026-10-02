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

parsedescription() {
    description=()

    if [[ -n "${param[description]:-}" ]]; then
	if ! mapfile_from_json description "${param[description]}" ; then
            printf '[ERROR] Argument parsing error\n' >&2
            exit 1
        fi
    fi
}

declare -a description=()
parsedescription

# Disable glob expansion
$MAIA_BIN task update "${param[task]}" "${param[version]}" "${description[@]}"
