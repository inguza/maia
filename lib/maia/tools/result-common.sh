#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

. "$MAIA_CORE_LIB_DIR/fast.sh"

parseresult() {
    local output status=0

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
        '
    ); then
        status=$?
        printf '[ERROR] Argument parsing error\n' >&2
        exit "$status"
    fi

    # It will loop at least once so we need to check against empty key
    while IFS=$'\t' read -r key value; do
	[[ -n "$key" ]] || continue
	# No \r for windows users because that makes bash hang on Linux with large data
        param["$key"]="${value}"
    done <<< "$output"
}
