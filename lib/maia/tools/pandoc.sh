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

command="pandoc"

declare -A allowed
for arg in "$@"; do
    allowed["$arg"]=1
done

declare -a args
arguments=${param[arguments]:-}
for argument in $arguments; do
    if [[ -z "${allowed[$argument]+x}" ]]; then
        echo "[ERROR] Argument '$argument' is not allowed for '$command': $argument" >&2
	exit 2
    fi
    args+=("$argument")
done

pathspec="${param[path]:-}"
for path in $pathspec ; do
    validate_path "$path"
done
if="${param[input-format]}"
if [[ -n "$if" && "$if" =~ ^[0-9a-zA-Z]+$ ]] ; then
    args+=(-f $if)
fi
of="${param[output-format]}"
if [[ -n "$of" && "$of" =~ ^[0-9a-zA-Z]+$ ]] ; then
    args+=(-t $of)
fi

# Disable glob expansion
$command "${args[@]}" $pathspec
