#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

parseparam() {
    local output status

    if ! output=$(
        jq -r '
            to_entries[]
            | [
                .key,
                (if (.value | type) == "string"
                 then .value
                 else (.value | tojson)
                 end)
              ]
            | @tsv
        ' <&3
    ); then
        status=$?
        printf '[ERROR] Argument parsing error\n' >&2
        exit "$status"
    fi

    # It will loop at least once so we need to check against empty key
    while IFS=$'\t' read -r key value; do
	[[ -n "$key" ]] || continue
        param["$key"]="$value"
    done <<< "$output"
}

parsearguments() {
    arguments=()

    if [[ -n ${param[arguments]:-} ]]; then
        local output

        if output=$(jq -r '.[]' <<< "${param[arguments]}" 2> /dev/null ) ; then
            if [[ -n "$output" ]]; then
                mapfile -t arguments <<< "$output"
            fi
        else
            printf '[ERROR] Argument parsing error\n' >&2
            exit 1
        fi
    fi
}

validate_path()
{
    local path="$1"

    # Must be relative
    if [[ "$path" == /* || "$path" == "~"* ]]; then
        echo "[ERROR] Path must be relative to the workspace: $path"
	exit 1
    fi

    # No .. path components
    if [[ "$path" == ".." || "$path" == ../* || "$path" == */../* || "$path" == */.. ]]; then
        echo "[ERROR] Path must not contain '..': $path"
	exit 2
    fi
}
