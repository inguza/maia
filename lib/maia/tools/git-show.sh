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
command="git show"

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

objects="${param[objects]:-}"
declare -a objs=()
if [[ -n "$objects" ]]; then
    if ! mapfile_from_json objs "$objects"; then
        echo "[ERROR] objects parse error." >&2
        exit 2
    fi
fi
git show "${args[@]}" "${objs[@]}"
