#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

. "$MAIA_CORE_LIB_DIR/fast.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam

command="$1"
shift

declare -A allowed

for arg in "$@"; do
    allowed["$arg"]=1
done

declare -a args
lines="${param[lines-context]:-}"
if [[ -n "$lines" && "$lines" =~ ^[0-9]+$ ]] ; then
    args+=(-n $lines)
fi

pathspecs="${param[pathspecs]:-}"
declare -a paths=()
if [[ -n "$pathspecs" ]] ; then
    mapfile_from_json paths "$pathspecs"
fi
for path in "${paths[@]}" ; do
    validate_path "$path"
done
$command "${args[@]}" "${paths[@]}"
