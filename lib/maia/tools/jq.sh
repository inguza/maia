#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

#if [[ ! -v "param[filter]" ]]; then
#    die "Missing filter parameter"
#fi

#declare -a filepatterns=()
#if [[ -n ${param[filepatterns]:-} ]]; then
#    mapfile -t filepatterns < <(
#        jq -r '.[]' <<< "${param[filepatterns]}"
#    )
#fi
#check_patterns() {
#    while [[ $# -gt 0 ]]; do
#	validate_path "$1"
#	shift
#    done
#}

#check_patterns "${filepatterns[@]}"

set -eo pipefail

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"

declare -A param
parseparam

declare -a arguments=()
parsearguments

declare -a usearguments=()

expand_pattern() {
    local pattern="$1"
    local -a matches

    if [[ "$pattern" == *[\*\?\[]* ]]; then
        mapfile -t matches < <(compgen -G "$pattern")

        if ((${#matches[@]})); then
            printf '%s\n' "${matches[@]}"
        else
            printf '%s\n' "$pattern"
        fi
    else
        printf '%s\n' "$pattern"
    fi
}

check_arguments() {
    local filter_seen=false
    while [[ $# -gt 0 ]]; do
	local arg="$1"
	shift
	case "$arg" in
	    --slurp|-s|--stream|--tab|--sort-keys|-S|-r|--raw-output|-e|--raw-input|-R|--null-input|-n|-c|--compact-output)
		usearguments+=("$arg")
		;;
	    -f)
		usearguments+=("$arg")
		local file="$1"
		validate_path "$file"
		shift
		usearguments+=("$file")
		filter_seen=true
		;;
	    --arg|--argjson)
		usearguments+=("$arg")
		local name="$1"
		shift
		usearguments+=("$name")
		local val="$1"
		shift
		usearguments+=("$val")
		;;
	    --slurpfile|--argfile)
		usearguments+=("$arg")
		local name="$1"
		shift
		usearguments+=("$name")
		local file="$1"
		validate_path "$file"
		shift
		usearguments+=("$file")
		;;
	    --args|--jsonargs)
		usearguments+=("$arg")
		usearguments+=("$@")
		break
		;;
	    *)
		if [[ "$filter_seen" == false ]] ; then
		    filter_seen=true
		    usearguments+=("$arg")
		else
		    # Treat as file
		    validate_path "$arg"
		    mapfile -t matches < <(expand_pattern "$arg")
		    usearguments+=("${matches[@]}")
		fi
		;;
	esac
    done    
}

check_arguments "${arguments[@]}"

jq "${usearguments[@]}"
