#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

. "$MAIA_CORE_LIB_DIR/fast.sh"

parseparam() {
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
        ' <&3
    ); then
        status=$?
        printf '[ERROR] Argument parsing error\n' >&2
        exit "$status"
    fi

    # It will loop at least once so we need to check against empty key
    while IFS=$'\t' read -r key value; do
	[[ -n "$key" ]] || continue
	# Remove \r for windows users
        param["$key"]="${value%$'\r'}"
    done <<< "$output"
}

parsearguments() {
    arguments=()

    if [[ -n "${param[arguments]:-}" ]]; then
	if ! mapfile_from_json arguments "${param[arguments]}" ; then
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

prune_tool_call_arguments() {
    local history_file="$(resolve_history_meta)"
    if [[ -s "$history_file" ]] ; then
	exclusive_json_modify \
	    "$history_file" \
	    --arg source "$TOOL_CALL_ID" \
	    -f "$MAIA_HOOKS_LIB_DIR/prune-tool-call-args.jq"
    fi
}
