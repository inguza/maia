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

command="curl"

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

url="$(printf '%b' "${param[url]:-}")"

if [[ -v "param[json]" ]] ; then
    args+=(--json "$(printf '%b' "${param[json]}")")
fi

for d in "data" "data-raw" "data-binary" "header" ; do
    if [[ -v "param[$d]" ]] ; then
	while IFS= read -r value; do
	    args+=(--$d "$value")
	done < <(jq -r '.[]' <<< "$(printf '%b' "${param[$d]}")")
    fi
done

# Disable glob expansion
$command --no-progress-meter "${args[@]}" "$url"
