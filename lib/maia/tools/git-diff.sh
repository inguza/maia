#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

subcmd="diff"
command="git $subcmd"

. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam

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

declare -a paths=()
parsepathspecs pathspecs
treeish="${param[tree-ish]}"

declare -a diff_args=("${args[@]}")

if [[ -n "$treeish" ]] ; then
    diff_args+=("$treeish")
fi

if [[ ${#paths[@]} -gt 0 ]] ; then
    diff_args+=("--" "${paths[@]}")
fi

git "$subcmd" "${diff_args[@]}"
