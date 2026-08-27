#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam

while IFS= read -r id; do
    # TODO check that id does not contain any unknown characters
    "$MAIA_BIN" change skipped "$id"
done < <(jq -r '.[]' <<< "$(printf '%b' "${param[id]}")")
