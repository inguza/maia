#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

parseparam() {
    # Read the parameters from fd 3
    while IFS=$'\t' read -r key value; do
	param["$key"]="$value"
    done < <(
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
    )
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
        echo "[ERROR] Path may not contain '..': $path"
	exit 2
    fi
}
