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

# "filepatterns" is the legacy name, files have precedence
fileparam="filepatterns"
if [[ -v param[files] ]] ; then
    fileparam="files"
fi

if [[ ! -v param[$fileparam] ]] ; then
    die "Missing parameter $fileparam."
fi

filedefs=()
while IFS= read -r filepattern; do
    filedefs+=("$filepattern")
done < <(jq -r '.[]' <<< "$(printf '%b' "${param[$fileparam]}")")

# Start code for subsession-file-forget
subsession="${param[subsession]:-}"
if [[ -n "$subsession" ]] ; then
    validate_subsession "$subsession"
    thissession="$(resolve_session_name)"
    set_subsession "$subsession"
    "$MAIA_BIN" file forget "${filedefs[@]}" 2>&1 | session_filter "$thissession"
# End code for subsession-file-forget
else
    "$MAIA_BIN" file forget "${filedefs[@]}" 2>&1
fi
