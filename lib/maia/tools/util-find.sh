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
namepattern="$(printf '%b' "${param[name]:-}")"
if [[ -n "$namepattern" ]] ; then
    args+=(-name "$namepattern")
fi
# Type
type="${param[type]:-}"
if [[ -n "$type" ]] ; then
    args+=(-type "$type")
fi
# Path
pathpattern="$(printf '%b' "${param[path]:-}")"
if [[ -n "$pathpattern" ]] ; then
    args+=(-path "$pathpattern")
fi
# Ipath
ipathpattern="$(printf '%b' "${param[ipath]:-}")"
if [[ -n "$ipathpattern" ]] ; then
    args+=(-ipath "$ipathpattern")
fi

pathspecs="${param[pathspecs]:-}"
declare -a paths=()
if [[ -n "$pathspecs" ]] ; then
    if ! mapfile_from_json paths "$pathspecs" ; then
	echo "[ERROR] pathspecs parse error."
	exit 3
    fi
fi
for path in "${paths[@]}" ; do
    validate_path "$path"
done
find -P "${paths[@]}" "${args[@]}" | grep -v "/\."
