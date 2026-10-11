#!/bin/bash

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/result-common.sh"

declare -A param
parseresult

action="${param[action]}"
if [[ -n "$action" ]] ; then
    printf 'Search action: %s\n' "$action"
fi
# Results is only occurring the request includes:
# "include": ["web_search_call.results"]
# MAIA does not currently support configuring this, but handle it just in case.
results="${param[results]}"
if [[ -n "$results" ]] ; then
    printf 'Search results: %s\n' "$results"
fi
exit 0
