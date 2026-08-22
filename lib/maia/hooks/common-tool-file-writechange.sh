#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

change_state_change_common() {
    local history_file="$(resolve_history_meta)"
    local event=$1
    shift
    for changef in $@ ; do
	[[ "$changef" == *+* ]] && continue

	local prune_id="$(basename "$changef")"
	prune_id="${prune_id%-*.json}"
	prune_id="${prune_id%-*}"
	local source=$(jq -r '.source' "$changef") || continue
	if [[ "$source" == call_* ]]; then
	    # Prune the history in the followning way:
	    # - Look up role=tool entries with tool_call_id=$source and prune the patch content part
	    # - Look up role=assistant entries that has a tool_call with id=$source and prune the arguments
	    exclusive_json_modify \
		"$history_file" \
		--arg source "$source" \
		--arg prune_id "$prune_id" \
		-f "$MAIA_HOOKS_LIB_DIR/prune-proposed-change-content.jq"
	fi
    done
}
