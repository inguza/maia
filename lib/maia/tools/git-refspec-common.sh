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

declare -A allowed

subcmd="$1"
shift

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

repository="${param[repository]}"
refspecs="${param[refspecs]:-}"
declare -a refs=()
if [[ -n "$refspecs" ]] ; then
    mapfile_from_json refs "$refspecs"
fi

if [[ -n "$repository" ]] ; then
    git "$subcmd" "${args[@]}" "$repository" "${refs[@]}"
else
    git "$subcmd" "${args[@]}"
fi
