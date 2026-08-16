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

pathspec="${param[pathspec]:-}"
for path in $pathspec ; do
    validate_path "$path"
done
$command "${args[@]}" $pathspec
# Exit with 0 since otherwise you get an error when there is no match
exit 0
