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

fileparam="files"
if [[ -v param[filepatterns] ]] ; then
    # Backwards compatibility
    fileparam="filepatterns"
fi

if [[ ! -v param[$fileparam] ]] ; then
    die "Missing parameter $fileparam."
fi

startline="${param[startline]:-}"
stopline="${param[stopline]:-}"

filedefs=()
if ! mapfile_from_json filepatterns "${param[$fileparam]}" ; then
    die "$fileparam parse error."
fi
for filepattern in "${filepatterns[@]}" ; do
    if [[ "$filepattern" == *'#'* ]]; then
        warn "$filepattern is a resource, not a file. This tool only handles files."
        continue
    fi
    mapfile_from_command files compgen -G "$filepattern" || true
    if [[ ${#files[@]} == 0 ]] ; then
	warn "File '$filepattern' not found, skipping."
    fi
    for file in "${files[@]}"; do
	if [[ -d "$file" ]] ; then
	    warn "$file is a directory, skipping."
	    continue
	fi
	if [[ ! -f "$file" ]] ; then
	    # Unlikely to appear but it could happen if the file is just removed
	    warn "$file not found, skipping."	    
	fi
	if [[ -n "$startline" || -n "$stopline" ]] ; then
	    filedefs+=("$file:$startline-$stopline")
	else
	    filedefs+=("$file")
	fi
    done
done

if [[ "$TOOL_NAME" == "subsession-file-remember" ]] ; then
    subsession="${param[subsession]:-}"
    thissession="$(resolve_session_name)"
    set_subsession "$subsession"
    "$MAIA_BIN" file remember "${resourcedefs[@]}" 2>&1 | session_filter "$thissession"
else
    "$MAIA_BIN" file remember "${filedefs[@]}"
fi
