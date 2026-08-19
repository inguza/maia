#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

. "$MAIA_TOOLS_LIB_DIR/common.sh"
declare -A param
parseparam

command="find"

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

# Min depth
mindepth="${param[mindepth]:-}"
if [[ -n "$mindepth" && "$mindepth" =~ ^[0-9]+$ ]] ; then
    args+=(-mindepth $mindepth)
fi
# Max depth
maxdepth="${param[maxdepth]:-}"
if [[ -n "$maxdepth" && "$maxdepth" =~ ^[0-9]+$ ]] ; then
    args+=(-maxdepth $maxdepth)
fi
# Name
namepattern="${param[name]:-}"
if [[ -n "$namepattern" ]] ; then
    args+=(-name "$namepattern")
fi
# Type
type="${param[type]:-}"
if [[ -n "$type" ]] ; then
    args+=(-type "$type")
fi
# Path
pathpattern="${param[path]:-}"
if [[ -n "$pathpattern" ]] ; then
    args+=(-path "$pathpattern")
fi
# Ipath
ipathpattern="${param[ipath]:-}"
if [[ -n "$ipathpattern" ]] ; then
    args+=(-ipath "$ipathpattern")
fi

paths=()
pathspec="${param[pathspec]:-}"
for path in $pathspec ; do
    validate_path "$path"
    paths+=("$path")
done
find -P "${paths[@]}" "${args[@]}" | grep -v "/\."
