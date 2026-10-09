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
    local maia_home="${MAIA_HOME:-}"
    while [ "$dir" != "/" ]; do
	# Stop early if we hit $maia_home or the user's home
	if [[ "$dir" == "$maia_home" || "$dir" == "$HOME" ]] ; then
	    break
	fi
	maia_data_search_path+=("$dir")
	dir=$(dirname "$dir")
    done

    if [ -n "$maia_home" ] ; then
	maia_data_search_path+=("$maia_home")
    fi
    maia_data_search_path+=("$HOME" "/etc")

    # Check for .maia directories in each directory in maia_data_search_path
    # Check each candidate: use “maia” under /etc, otherwise “.maia”
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

    # If no valid .maia directory is found, fallback to $maia_home or ~/.maia
    if [ ${#data_paths[@]} -eq 0 ]; then
	if [ -n "$maia_home" ]; then
	    data_paths+=("$maia_home/.maia")
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
        ws="$(read_session_workspace_raw "$sess_name")"
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
	myl_get "$ws_meta" 'path'
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
	myl_get "$sess_meta" 'workspace'
    fi
}

read_session_profile_raw() {
    local sess_name="$1"
    local sess_meta="$(resolve_session_meta "$sess_name")"
    if [[ -e "$sess_meta" ]] ; then
	myl_get "$sess_meta" 'profile'
    fi
}

################################################################################################################

resolve_profile_base() { resolve_x_base "profile" ; }

resolve_profile_name() {
    local profile="$1"
    if [[ -z "$profile" ]]; then
        # Indirection to session workspace
        local sess_name="$(resolve_session_name)"
        profile="$(read_session_profile_raw "$sess_name")"
    fi
    echo "$profile"
}

resolve_profile_meta() {
    echo -n ""
}

################################################################################################################

resolve_x_base() {
    echo "$(resolve_home_dir)/${1}s"
}

# Full path to the metadata file ($2.myl)
# Accepts an optional name, else uses the active workspace.
resolve_x_meta() {
    local path="$(resolve_${1}_path "$3")"
    if [[ -n "$path" ]] ; then
	case "$2" in
	    history)
		echo "$path/$2.json"
		;;
	    *)
		echo "$path/$2.myl"
		;;
	esac
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

# Not fully needed in this file but does not hurt the performance

copya() {
    local -n _src="$1"
    local -n _dest="$2"
    for key in "${!_src[@]}"; do
	_dest["$key"]="${_src[$key]}"
    done
}

# Load a MYL file into an associative array.
# Usage: myl_load <associative-array-name> <file>
#
# A MYL entry has the form:
#
#   key: value
#
# or, for a multiline value:
#
#   key:
#     first line
#     second line
#
# The two-space indentation is removed from multiline values.  Existing
# entries in the destination array are replaced when the same key occurs in
# the file; keys not present in the file are left untouched.
myl_load() {
    local file="$1"
    local -n _dest="$2"

    [[ -n "$file" ]] || return 2
    [[ -f "$file" ]] || return 1

    local line key value current="" first_continuation=1

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Be tolerant of files created on Windows.
        line="${line%$'\\r'}"

        # A line beginning with two spaces belongs to the preceding key.
        if [[ "$line" == "  "* && -n "$current" ]]; then
            value="${line:2}"
            if (( first_continuation )); then
                _dest["$current"]="$value"
                first_continuation=0
            else
                _dest["$current"]+=$'\\n'"$value"
            fi
            continue
        fi

        # A non-indented line ends the preceding multiline value.
        current=""
        first_continuation=1

        # Keys cannot contain whitespace or a colon.  Permit an empty value;
        # it is useful for fields such as `description:`.
        if [[ "$line" =~ ^([^:[:space:]]+):[[:space:]]?(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            _dest["$key"]="$value"
            current="$key"
        fi
    done < "$file"
}

myl_merge() {
    local -A values=() multiline=() seen=()
    local -a order=()
    local file line key value current="" is_multiline=0

    for file in "$@"; do
        [[ -f "$file" ]] || continue
        current=""
        is_multiline=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            if (( is_multiline )) && [[ "${line:0:2}" == "  " ]]; then
                values["$current"]+="${line}"$'\n'
                continue
            fi

            if (( is_multiline )); then
                is_multiline=0
                current=""
            fi

            if [[ "$line" =~ ^([^:[:space:]]+):[[:space:]]?(.*)$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                if [[ ! -v seen[$key] ]]; then
                    seen["$key"]=1
                    order+=("$key")
                fi
                values["$key"]="$value"
                multiline["$key"]=0
                current="$key"
                if [[ -z "$value" ]]; then
                    is_multiline=1
                    multiline["$key"]=1
                fi
            fi
        done < "$file"
    done

    for key in "${order[@]}"; do
        if [[ "${multiline[$key]}" == 1 ]]; then
            printf '%s:\n%s' "$key" "${values[$key]}"
        else
            printf '%s: %s\n' "$key" "${values[$key]}"
        fi
    done
}

myl_pretty() {
    local file="$1"
    local heading="$2"
    local heading_extra="$3"
    local line key value current="" multiline=0 pretty_key

    [[ -f "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( multiline )) && [[ "${line:0:2}" == "  " ]]; then
            printf '%s\n' "$line"
            continue
        fi
        multiline=0

        if [[ "$line" =~ ^([^:[:space:]]+):[[:space:]]?(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            pretty_key="${key^}"
            if [[ "$key" == "$heading" ]]; then
                printf '%s# %s: %s\n\n' "$heading_extra" "$pretty_key" "$value"
            else
                printf '%s: %s\n' "$pretty_key" "$value"
            fi
            [[ -n "$value" ]] || multiline=1
        fi
    done < "$file"
}

myl_add() {
    local file="$1"
    local field="$2"
    shift 2

    if (( $# == 0 )); then
	printf '%s:\n' "$field" >> "$file"
    elif (( $# == 1 )); then
	printf '%s: %s\n' "$field" "$1" >> "$file"
    else
	printf '%s:\n' "$field" >> "$file"
	printf '  %s\n' "$@" >> "$file"
    fi
}

myl_update() {
    local file="$1"
    local field="$2"
    shift 2

    if [[ ! -f "$file" ]]; then
        myl_add "$file" "$field" "$@"
        return
    fi

    local tmpfile="${file}.tmp.$$"
    local line remainder found=0 skip=0 prefix="$field:"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( skip )); then
            if [[ "${line:0:2}" == "  " ]]; then
                continue
            fi
            skip=0
        fi

        if (( ! found )) && [[ "${line:0:${#prefix}}" == "$prefix" ]]; then
            remainder="${line:${#prefix}}"
            if [[ -z "$remainder" || "${remainder:0:1}" == " " ]]; then
                if (( $# == 0 )); then
                    printf '%s:\n' "$field"
                elif (( $# == 1 )); then
                    printf '%s: %s\n' "$field" "$1"
                else
                    printf '%s:\n' "$field"
                    printf '  %s\n' "$@"
                fi
                found=1
                [[ -z "$remainder" ]] && skip=1
                continue
            fi
        fi

        printf '%s\n' "$line"
    done < "$file" > "$tmpfile" || {
        rm -f "$tmpfile"
        return 1
    }

    if (( ! found )); then
        myl_add "$tmpfile" "$field" "$@"
    fi

    mv "$tmpfile" "$file"
}

# Delete a key and its value from a MYL file.
# Usage: myl_delete <file> <key>
#
# A key with an indented multiline value removes the complete block.  The
# original file is replaced atomically only after the rewrite succeeds.
myl_delete() {
    local file="$1"
    local field="$2"

    [[ -n "$file" && -n "$field" ]] || return 2
    [[ -f "$file" ]] || return 1

    local tmpfile="${file}.tmp.$$"
    local line remainder prefix="${field}:" found=0 skip=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( skip )); then
            if [[ "${line:0:2}" == "  " ]]; then
                continue
            fi
            skip=0
        fi

        if (( ! found )) && [[ "${line:0:${#prefix}}" == "$prefix" ]]; then
            remainder="${line:${#prefix}}"
            # Match the complete key, not similarly prefixed keys such as
            # `status` when deleting `state`.
            if [[ -z "$remainder" || "${remainder:0:1}" == " " ]]; then
                found=1
                if [[ -z "$remainder" ]]; then
                    skip=1
                fi
                continue
            fi
        fi

        printf '%s\n' "$line"
    done < "$file" > "$tmpfile" || {
        rm -f "$tmpfile"
        return 1
    }

    mv -- "$tmpfile" "$file"
}

myl_append() {
    local file="$1"
    local field="$2"
    shift 2

    if [[ ! -f "$file" ]]; then
        myl_add "$file" "$field" "$@"
        return
    fi

    local tmpfile="${file}.tmp.$$"
    local line remainder value found=0 in_block=0 prefix="$field:"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( in_block )); then
            if [[ "${line:0:2}" == "  " ]]; then
                printf '%s\n' "$line"
                continue
            fi
            for value in "$@"; do
                printf '  %s\n' "$value"
            done
            in_block=0
        fi

        if (( ! found )) && [[ "${line:0:${#prefix}}" == "$prefix" ]]; then
            remainder="${line:${#prefix}}"
            if [[ -z "$remainder" || "${remainder:0:1}" == " " ]]; then
                printf '%s:\n' "$field"
                while [[ "${remainder:0:1}" == " " ]]; do
                    remainder="${remainder:1}"
                done
                if [[ -n "$remainder" ]]; then
                    printf '  %s\n' "$remainder"
                fi
                if [[ -z "$remainder" ]]; then
                    in_block=1
                else
                    for value in "$@"; do
                        printf '  %s\n' "$value"
                    done
                fi
                found=1
                continue
            fi
        fi

        printf '%s\n' "$line"
    done < "$file" > "$tmpfile" || {
        rm -f "$tmpfile"
        return 1
    }

    if (( in_block )); then
        for value in "$@"; do
            printf '  %s\n' "$value"
        done >> "$tmpfile"
    fi

    if (( ! found )); then
        myl_add "$tmpfile" "$field" "$@"
    fi

    mv "$tmpfile" "$file"
}

myl_get() {
    local file="$1"
    local field="$2"
    if [[ ! -f "$file" ]] ; then
	return 1
    fi
    local prefix="$field:"
    local line value found=0

    while IFS= read -r line || [[ -n "$line" ]]; do
	if (( ! found )); then
	    [[ "${line:0:${#prefix}}" == "$prefix" ]] || continue
	    value="${line:${#prefix}}"
	    [[ -z "$value" || "${value:0:1}" == " " ]] || continue
	    while [[ "${value:0:1}" == " " ]]; do
		value="${value:1}"
	    done
	    if [[ -n "$value" ]]; then
		printf '%s' "$value"
		return 0
	    fi
	    found=1
	    continue
	fi

	if [[ "${line:0:2}" == "  " ]]; then
	    printf '%s\n' "${line:2}"
	else
	    return 0
	fi
    done < "$file"
    return 0
}

# Git Bash workaround
normalize_lf() {
    local -n _xdst="$1"
    local i

    for i in "${!_xdst[@]}"; do
        _xdst[i]="${_xdst[i]%$'\r'}"
    done
}

read_file_by_line() {
    local filename="$1"
    local filter="$2"
    local input=/dev/stdin
    [[ -n "$filename" ]] && input="$filename"

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
	case "$filter" in
	    cr)
		line="${line%$'\r'}"
		;;
	    *)
		:
		;;
	esac
	printf '%s\n' "$line"
    done < "$input"
}

read_file() {
    local filename="$1"
    local filter="$2"
    local input=/dev/stdin
    [[ -n "$filename" ]] && input="$filename"

    while true; do
	local line
	IFS= read -r line
	local status=$?
	[[ $status -eq 0 || -n "$line" ]] || break
	case "$filter" in
	    cr)
		line="${line%$'\r'}"
		;;
	    *)
		:
		;;
	esac
	if [[ $status -eq 0 ]]; then
	    printf '%s\n' "$line"
	else
            printf '%s' "$line"
	fi
    done < "$input"
}

mapfile_from_command_nolf() {
    local -n _dst="$1"
    shift
    local tmpfile="$(mktemp)"
    local status=0
    "$@" > "$tmpfile" || status=$?
    mapfile -t _dst < "$tmpfile"
    rm -f "$tmpfile"
    return $status
}

mapfile_from_command() {
    local -n _dst="$1"
    shift
    local tmpfile="$(mktemp)"
    local status=0
    "$@" > "$tmpfile" || status=$?
    mapfile -t _dst < "$tmpfile"
    rm -f "$tmpfile"
    normalize_lf _dst
    return $status
}

mapfile_from_json() {
    local -n _dst="$1"
    local json="$2"
    local tmpfile="$(mktemp)"
    local status=0
    if [[ -n "$json" ]] ; then
	jq -r '.[]' <<<"$json" > "$tmpfile" 2>/dev/null
	status=$?
    fi
    mapfile -t _dst < "$tmpfile"
    normalize_lf _dst
    rm -f "$tmpfile"
    return $status
}

mapfile_from_file() {
    local -n _dst="$1"
    local file="$2"
    mapfile -t _dst < "$file"
    normalize_lf _dst
}
