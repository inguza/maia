# Session handling
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
#

resolve_subsession_name() {
    local session="$1"
    local thissession="$(resolve_session_name)"
    echo "${thissession}%${session}"
}

# Set session, primarily from tools point of view
set_subsession() {
    local session="$1"
    if [[ ! "$session" =~ ^[a-zA-Z0-9._,:=+-]+$ ]]; then
	die "Invalid session name $session: Only letters, digits, . _ - , : = + are allowed." >&2
    fi
    local subsession="$(resolve_subsession_name "$1")"
    local path="$(resolve_session_path "${subsession}")"
    if [[ ! -d "$path" ]] ; then
	die "Invalid session name $session: Session does not exist." >&2
    fi
    export MAIA_SESSION="${subsession}"
}

session_filter() {
    local parent="$1"
    sed "s/$parent%//g;"
}
