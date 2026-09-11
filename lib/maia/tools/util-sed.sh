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

command="sed"

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

filespecs="${param[filespecs]:-}"
declare -a paths=()
if [[ -n "$filespecs" ]] ; then
    if ! mapfile_from_json paths "$filespecs" ; then
	echo "[ERROR] filespecs parse error." >&2
	exit 3
    fi
fi
for path in "${paths[@]}" ; do
    validate_path "$path"
done
script="$(printf '%b' "${param[script]}")"

# Disable glob expansion
$command --sandbox "${args[@]}" -e "$script" "${paths[@]}"
