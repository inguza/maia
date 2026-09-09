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

treeish="${param[tree-ish]}"
pathspecs="${param[pathspecs]:-}"
declare -a paths=()
if [[ -n "$pathspecs" ]] ; then
    mapfile -t paths < <(jq -r '.[]' <<< "$pathspecs")
fi
for path in "${paths[@]}" ; do
    validate_path "$path"
done

declare -a reset_args=("${args[@]}")
if [[ -n "$tree-ish" ]] ; then
    reset_args+=("$tree-ish")
fi
if [[ ${#paths[@]} -gt 0 ]] ; then
    reset_args+=("--" "${paths[@]}")
fi

git "$subcmd" "${reset_args[@]}"
