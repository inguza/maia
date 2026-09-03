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

id="${param[id]:-}"
force="${param[force]:-}"

if [[ -z "$id" ]]; then
    echo "Missing required parameter: id" >&2
    exit 1
fi

# Normalize force to a boolean-like value
if [[ "$force" == "true" || "$force" == "1" ]]; then
    "$MAIA_BIN" job delete --force "$id"
else
    "$MAIA_BIN" job delete "$id"
fi
