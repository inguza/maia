#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/session-common.sh"
declare -A param
parseparam

if [[ ! -v param[resources] ]] ; then
    die "Missing parameter resources."
fi


resourcedefs=()
if ! mapfile_from_json resourcepatterns "${param[resources]}" ; then
    die "resources parse error."
fi
for resourcepattern in "${resourcepatterns[@]}" ; do
    # TODO later
    #mapfile_from_command resources compgen -G "$resourcepattern" || true
    resource="$resourcepattern"
    #if [[ ${#resources[@]} == 0 ]] ; then
#	warn "Resource '$resourcepattern' not found, skipping."
#    fi
#    for resource in "${resources[@]}"; do
    if [[ "$resource" != *'#'* ]] ; then
	warn "$resource is file, not a resource. This tool only handles resources."
	continue
    fi
    resourcedefs+=("$resource")
done

if [[ "$TOOL_NAME" == "subsession-resource-remember" ]] ; then
    subsession="${param[subsession]:-}"
    set_subsession "$subsession"
    "$MAIA_BIN" file remember "${resourcedefs[@]}" 2>&1 | session_filter
else
    "$MAIA_BIN" file remember "${resourcedefs[@]}"
fi
