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
declare -a arguments=()
parsearguments

for argument in "${arguments[@]}"; do
    if [[ -z "${allowed[$argument]+x}" ]]; then
        echo "[ERROR] Argument '$argument' is not allowed for '$command': $argument" >&2
	exit 2
    fi
    args+=("$argument")
done

pathspecs="${param[pathspecs]:-}"
declare -a paths=()
if [[ -n "$pathspecs" ]] ; then
    if ! mapfile_from_json paths "$pathspecs" ; then
	echo "[ERROR] pathspecs parse error." >&2
	exit 2
    fi
fi
for path in "${paths[@]}" ; do
    validate_path "$path"
done
$command "${args[@]}" "${paths[@]}"
