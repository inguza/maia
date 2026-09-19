#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

profile_usage() {
    cat <<'EOF'
USAGE

  maia profile <command> [options]

Manage profile manifests and their filesets.

COMMANDS

  create <name>

  list|ls
    List all available profiles.

  delete [--force] <name>
    Delete the specified profile (cannot delete the current one).

OPTIONS

  -h, --help
    Show this help message for the "profile" subcommand.

EOF
    exit 0
}

handle_profile_command() {
    [[ "$1" =~ ^-h|--help$ ]] && profile_usage
    [[ "$2" =~ ^-h|--help$ ]] && profile_usage

    local cmd="${1:-}"

    case "$cmd" in
	create)
	    shift
	    local name="$1"
	    if [[ -z "$name" ]] ; then
		die "Must provide a name."
	    fi
	    local profile_dir=$(resolve_profile_path "$name")
	    mkdir -p "$profile_dir"
	    notice "Created profile '$name'."
	    ;;

	list|ls)
	    shift
	    handle_x_list profile
	    ;;

	delete)
	    shift
	    local FORCE=false
	    # Parse options before name
	    while [[ $# -gt 0 && "$1" == --* ]]; do
		case "$1" in
		    --force) FORCE=true; shift ;;
		    *) die "Unknown option: $1" ;;
		esac
	    done
	    local name="$1"
	    [[ -n "$name" ]] || die "Profile name required."
	    if [[ "$FORCE" != true ]]; then
		# 1) Prevent deleting the active profile
		local active_profile=$(resolve_profile_name)
		if [[ "$name" == "$active_profile" ]]; then
		    die "Cannot delete the active profile '$name'. Switch to a different profile before deleting."
		fi
		# 2) Check if any session uses this profile
		local sessions_dir="$(resolve_session_base)"
		if [[ -d "$sessions_dir" ]]; then
		    shopt -s nullglob
		    for ses_dir in "$sessions_dir"/*; do
			[[ -d "$ses_dir" ]] || continue
			local ses_meta="$ses_dir/session.json"
			if [[ -f "$ses_meta" ]]; then
			    local ses_profile=$(jq -r '.profile // empty' "$ses_meta")
			    if [[ "$ses_profile" == "$name" ]]; then
				die "Cannot delete profile '$name' because session '$(basename "$ses_dir")' is currently using it."
			    fi
			fi
		    done
		fi
	    fi
	    handle_x_delete "profile" "$name"
            ;;

	"")
	    local profile="$(resolve_profile_name)"
	    if [[ ! -n "$profile" ]] ; then
		profile="-"
	    fi
	    echo "${profile}"
	    ;;	    

	*)
	    die "Unknown profile command: $cmd"
	    ;;
    esac
}
