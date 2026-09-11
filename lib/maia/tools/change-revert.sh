#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

. "$MAIA_CORE_LIB_DIR/fast.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam

# id is the legacy, ids has precedence
idskey="id"
if [[ -v param[ids] ]] ; then
    idskey="ids"
fi

mapfile_from_json ids "${param[$idskey]}"
for id in "${ids[@]}"; do
    # TODO check that id does not contain any unknown characters
    "$MAIA_BIN" change revert "$id"
done
