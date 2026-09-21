# Session handling
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
#

. "$MAIA_CORE_LIB_DIR/common.sh"
_cfg=$(load_merged_config session)

resolve_subsession_name() {
    local session="$1"
    local prefix="$(resolve_subsession_prefix)"
    echo "${prefix}${session}"
}

resolve_subsession_prefix() {
    local prefix="$(get_config 'agent_session_prefix')"
    local this="$(resolve_session_name)"
    prefix="${prefix//__SESSION_NAME__/$this}"
    printf '%s' "$prefix"
}

validate_subsession() {
    local session="$1"
    if [[ -z "$session" ]] ; then
	die "Invalid subsession name '$session'. Must not be empty."
    fi
    if [[ ! "$session" =~ ^[a-zA-Z0-9._,:=+-]+$ ]]; then
	die "Invalid session name '$session': Only letters, digits, . _ - , : = + are allowed." >&2
    fi
    local allowed
    read -ra allowed <<< "$(get_config 'agent_session_allowed')"
    if ! subsession_allowed "$session" "${allowed[@]}" ; then
	die "Session with name '$session' not allowed."
    fi
}

# Set session, primarily from tools point of view
set_subsession() {
    local session="$1"
    validate_subsession "$session"
    local subsession="$(resolve_subsession_name "$session")"
    local path="$(resolve_session_path "${subsession}")"
    if [[ ! -d "$path" ]] ; then
	die "Invalid subsession name '$session': Session does not exist." >&2
    fi
    export MAIA_SESSION="${subsession}"
}

subsession_allowed() {
    local session="$1"
    shift
    local pattern
    for pattern in "$@" ; do
	[[ "$session" == $pattern ]] && return 0
    done
    return 1
}

list_filter() {
    local allowed
    read -ra allowed <<< "$(get_config 'agent_session_allowed')"
    while read -r session || [[ -n "$session" ]] ; do
	if subsession_allowed "$session" "${allowed[@]}" ; then
	    printf "%s\n" "$session"
	fi
    done
}

# Used by the below functions. Yes a little ugly solution but it works.
# We need to set this before someone alter MAIA_SESSION
subsession_prefix="$(resolve_subsession_prefix)"

subsession_list() {
    "$MAIA_BIN" session list 2>&1 \
	| grep "^[[:space:]]*${subsession_prefix}" \
	| sed 's/^[[:space:]]*//;' \
	| session_filter \
	| list_filter
}

session_filter() {
    if [[ -n "${subsession_prefix}" && "$subsession_prefix" =~ [^a-zA-Z0-9]$ ]] ; then
	# To do filtering we need the prefix to end with with a non-alphanumeric character.
	# We intentionally do not put a requirement on the session name after because
	# that could result in information leak. Not a big one because it only reveals
	# the identity of the prefix, but anyway.
	sed "s/${subsession_prefix}//;"
    else
	sed "s/\r\n/\n/g;"
    fi
}
