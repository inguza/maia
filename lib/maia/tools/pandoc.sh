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

arguments=()
parsearguments

declare -a args
for argument in "${arguments[@]}"; do
    if [[ -z "${allowed[$argument]+x}" ]]; then
        echo "[ERROR] Argument '$argument' is not allowed for '$command': $argument" >&2
	exit 2
    fi
    args+=("$argument")
done

path="$(printf '%b' "${param[path]:-}")"
if [[ -n "$path" ]] ; then
    validate_path "$path"
fi
input_format="${param[input-format]}"
if [[ -n "$input_format" && "$input_format" =~ ^[0-9a-zA-Z]+$ ]] ; then
    args+=(-f $input_format)
fi
output_format="${param[output-format]}"
if [[ -n "$output_format" && "$output_format" =~ ^[0-9a-zA-Z]+$ ]] ; then
    args+=(-t $output_format)
fi

# Disable glob expansion
$command "${args[@]}" "$path"
