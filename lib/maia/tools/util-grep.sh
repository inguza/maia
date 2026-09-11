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

command="grep"

declare -A allowed
for arg in "$@"; do
    allowed["$arg"]=1
done

declare -a arguments=()
parsearguments

declare -a args
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
	exit 3
    fi
fi
for path in "${paths[@]}" ; do
    validate_path "$path"
done
searchpattern="$(printf '%b' "${param[searchpattern]}")"

before="${param["before-context"]:-}"
if [[ -n "$before" && "$before" =~ ^[0-9]+$ ]] ; then
    args+=(-B $before)
fi
after="${param["after-context"]:-}"
if [[ -n "$after" && "$after" =~ ^[0-9]+$ ]] ; then
    args+=(-A $after)
fi

# Disable glob expansion
$command "${args[@]}" "$searchpattern" "${paths[@]}"
