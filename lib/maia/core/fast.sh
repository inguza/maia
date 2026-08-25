# Fast common functions to speed up operations that are time-critical such as prompt query
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

# Resolve data directory
resolve_home_dir() {
    local home_paths=( $(resolve_home_paths) )
    echo "${home_paths[0]}"
}

# Resolves the DATA_PATHS based on maia_data_search_path
resolve_home_paths() {
    local data_paths=()
    # Check ancestor directories (one level at a time) starting from the current working directory
    local maia_data_search_path=()
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
	# Stop early if we hit $MAIA_HOME or the user's home
	if [[ "$dir" == "$MAIA_HOME" || "$dir" == "$HOME" ]] ; then
	    break
	fi
	maia_data_search_path+=("$dir")
	dir=$(dirname "$dir")
    done

    if [ -n "$MAIA_HOME" ] ; then
	maia_data_search_path+=("$MAIA_HOME")
    fi
    maia_data_search_path+=("$HOME" "/etc")

    # Check for .maia directories in each directory in maia_data_search_path
    # Check each candidate: use “aia” under /etc, otherwise “.maia”
    for dir in "${maia_data_search_path[@]}"; do
	if [[ "$dir" == "/etc" ]]; then
	    candidate="$dir/maia"
	else
	    candidate="$dir/.maia"
	fi

	if [ -d "$candidate" ]; then
	    data_paths+=("$candidate")
	fi
    done

    # If no valid .maia directory is found, fallback to $MAIA_HOME or ~/.maia
    if [ ${#data_paths[@]} -eq 0 ]; then
	if [ -n "$MAIA_HOME" ]; then
	    data_paths+=("$MAIA_HOME/.maia")
	else
	    data_paths+=("$HOME/.maia")
	fi
    fi

    echo "${data_paths[@]}"
}

################################################################################################################

resolve_workspace_base() { resolve_x_base "workspace" ; }

# Enhanced resolve_workspace_name() supporting __SESSION_WORKSPACE__ indirection
resolve_workspace_name() {
    local ws="$1"
    if [[ -z "$ws" ]]; then
        # Indirection to session workspace
        local sess_name="$(resolve_session_name)"
        local ws="$(read_session_workspace_raw "$sess_name")"
    fi
    echo "$ws"
}

# If you pass a name, it uses that; otherwise it uses the active workspace.
resolve_workspace_path() {
    resolve_x_path "workspace" "$1"
}

# Accepts an optional name, else uses the active workspace.
resolve_workspace_meta() {
    resolve_x_meta "workspace" "workspace" "$1"
}

resolve_workspace_root() {
    local ws_name=$1
    local ws_meta="$(resolve_workspace_meta "$ws_name")"
    if [[ -f "$ws_meta" ]] ; then
	# The below code mimics the behavior of the following command but is much faster
	#    echo "$(jq -r .path < "$ws_meta")"
	fast_jq "path" "$ws_meta"
    fi
}

################################################################################################################


resolve_session_base() { resolve_x_base "session" ; }

resolve_session_name() {
    local name="$1"
    if [[ -z "$name" ]] ; then
	if [[ -n "$MAIA_SESSION" ]]; then
	    name="$MAIA_SESSION"
	fi
    fi
    if [[ -z "$name" ]] ; then
	echo "default"
    fi
    echo "$name"
}

resolve_session_path() { resolve_x_path "session" "$1"; }

resolve_session_meta() { resolve_x_meta "session" "session" "$1" ; }

read_session_workspace_raw() {
    local sess_name="$1"
    local sess_meta="$(resolve_session_meta "$sess_name")"
    if [[ -e "$sess_meta" ]] ; then
	# The below code mimics the behavior of the following command but is much faster
	#    jq -r '.workspace // empty' < "$sess_meta"
	fast_jq "workspace" "$sess_meta"
    fi
}

################################################################################################################

resolve_x_base() {
    echo "$(resolve_home_dir)/${1}s"
}

# Full path to the metadata file ($2.json)
# Accepts an optional name, else uses the active workspace.
resolve_x_meta() {
    local path="$(resolve_${1}_path "$3")"
    if [[ -n "$path" ]] ; then
	echo "$path/$2.json"
    fi
}

# Full path to a x ($1) directory.
# If you pass a name ($2), it uses that; otherwise it uses the active x.
resolve_x_path() {
    local x="$1"
    local name="$2"
    if [[ -z "$name" ]]; then
	name="$(resolve_${x}_name)"
    fi
    if [[ -n "$name" ]]; then
	echo "$(resolve_${x}_base)/$name"
    fi
}

#
fast_jq() {
    local param="$1" jsonfile="$2"
    local line
    local val=""
    while IFS= read -r line; do
	case $line in
            '  "'$param'": "'*)
		val=${line#*'"'$param'": "'}
		val=${val%'",'}
		val=${val%'"'}
		break
		;;
	esac
    done < "$jsonfile"
    if [[ "$val" == "null" ]] ; then
	val=""
    fi
    echo "$val"
}
