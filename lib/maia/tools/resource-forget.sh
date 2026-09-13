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
    echo "[ERROR] resources parse error." >&2
    exit 2
fi
for resourcepattern in "${resourcepatterns[@]}" ; do
    if [[ "$resourcepattern" != *'#'* ]]; then
        warn "$resourcepattern is a file, not a resource. This tool only handles resources."
        continue
    fi
    resourcedefs+=("$resourcepattern")
done

if [[ "$TOOL_NAME" == "subsession-resource-forget" ]] ; then
    subsession="${param[subsession]:-}"
    validate_subsession "$subsession"
    thissession="$(resolve_session_name)"
    set_subsession "$subsession"
    "$MAIA_BIN" file forget "${resourcedefs[@]}" 2>&1 | session_filter "$thissession"
else
    "$MAIA_BIN" file forget "${resourcedefs[@]}" 2>&1
fi
