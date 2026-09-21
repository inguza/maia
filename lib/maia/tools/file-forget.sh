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
. "$MAIA_TOOLS_LIB_DIR/session-common.sh"

declare -A param
parseparam

# "filepatterns" is the legacy name, files have precedence
fileparam="filepatterns"
if [[ -v param[files] ]] ; then
    fileparam="files"
fi

if [[ ! -v param[$fileparam] ]] ; then
    die "Missing parameter $fileparam."
fi

filedefs=()
if ! mapfile_from_json filepatterns "${param[$fileparam]}" ; then
    echo "[ERROR] files parse error." >&2
    exit 2
fi
for filepattern in "${filepatterns[@]}" ; do
    if [[ "$filepattern" == *'#'* ]]; then
        warn "$filepattern is a resource, not a file. This tool only handles files."
        continue
    fi
    filedefs+=("$filepattern")
done

if [[ "$TOOL_NAME" == "session-file-forget" ]] ; then
    set_subsession "${param[session]:-}"
    "$MAIA_BIN" file forget "${resourcedefs[@]}" 2>&1 | session_filter
else
    "$MAIA_BIN" file forget "${filedefs[@]}" 2>&1
fi
