#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam

# id is the legacy, ids has precedence
idskey="id"
if [[ -v param[ids] ]] ; then
    idskey="ids"
fi

while IFS= read -r id; do
    if [[ -z "$id" ]]; then
	continue
    fi
    if [[ ! "$id" =~ ^[0-9]{8}T[0-9]{6}-[a-f0-9]+-[0-9]+$ ]]; then
        warn "Invalid change ID format: '$id', skipping."
        continue
    fi
    "$MAIA_BIN" change apply "$id"
done < <(jq -r '.[]' <<< "$(printf '%b' "${param[$idskey]}")")
