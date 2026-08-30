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
. "$MAIA_TOOLS_LIB_DIR/session-common.sh"
declare -A param
parseparam

filedefs=()
while IFS= read -r filepattern; do
    filedefs+=("$filepattern")
done < <(jq -r '.[]' <<< "$(printf '%b' "${param[filepatterns]}")")

thissession="$(resolve_session_name)"
subsession="${param[subsession]:-}"
# TODO check subsession name for unknown characters
if [[ -n "$subsession" ]] ; then
    set_subsession "$subsession"
fi
"$MAIA_BIN" file forget "${filedefs[@]}" 2>&1 | session_filter "$thissession"
