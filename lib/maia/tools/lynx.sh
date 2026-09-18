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

command="lynx"

declare -A allowed
for arg in "$@"; do
    allowed["$arg"]=1
done

declare -a arguments=()
parsearguments

urlencode_internal() {
    local input="$1"
    local output=""
    local i ch hex
    local LC_ALL=C

    for (( i=0; i<${#input}; i++ )); do
        ch="${input:i:1}"
        case "$ch" in
            [a-zA-Z0-9.~_-])
                output+="$ch"
                ;;
            ' ')
                output+='%20'
                ;;
            *)
                printf -v hex '%%%02X' "'${ch}"
                output+="$hex"
                ;;
        esac
    done

    printf '%s' "$output"
}

declare -a args
for argument in "${arguments[@]}"; do
    if [[ -z "${allowed[$argument]+x}" ]]; then
        echo "[ERROR] Argument '$argument' is not allowed for '$command': $argument" >&2
	exit 2
    fi
    args+=("$argument")
done

urls="${param[urls]:-}"
declare -a url_array=()
if [[ -n "$urls" ]] ; then
    if ! mapfile_from_json url_array "$urls" ; then
        echo "[ERROR] urls parse error." >&2
	exit 3
    fi
fi
if [[ ${#url_array[@]} -eq 0 ]] ; then
    query="$(printf '%b' "${param[query]:-}")"
    url_array=("https://html.duckduckgo.com/html/?q=$(urlencode_internal "$query")")
fi

# Disable glob expansion
$command -dump "${args[@]}" "${url_array[@]}"
