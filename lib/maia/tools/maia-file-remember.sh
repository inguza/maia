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

startline="${param[startline]:-}"
stopline="${param[stopline]:-}"

filepattern="$(printf '%b' "${param[filepattern]}")"
mapfile -t files < <(compgen -G "$filepattern")

filedefs=()
for file in "${files[@]}"; do
    if [[ -d "$file" ]] ; then
	warn "$file is a directory, skipping."
    fi
    if [[ -n "$startline" || -n "$stopline" ]] ; then
	filedefs+=("$file:$startline-$stopline")
    else
	filedefs+=("$file")
    fi
done

thissession="$(resolve_session_name)"
subsession="${param[subsession]:-}"
# TODO check subsession name for unknown characters
if [[ -n "$subsession" ]] ; then
    set_subsession "$subsession"
fi
"$MAIA_BIN" file remember "${filedefs[@]}" 2>&1 | session_filter "$thissession"
