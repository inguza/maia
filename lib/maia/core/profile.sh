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

  maia profile [--scope <scope>] <command> [options]

Manage profile manifests and their filesets.

COMMANDS

  create <name> [<description>]

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

list_profiles() {
    local scope="$1"
    local selected="$(resolve_profile_name)"
    local profilesdata="$(get_all_ordered_profile_names "description")"

    read -ra patterns <<< "$(get_config allowed_profiles)"

    printf '  %-22s%s\n' "NAME" "DESCRIPTION"
    printf '%s\n' "======================================================================="
    while IFS=' ' read -r profile description; do
	[[ -n "$profile" ]] || continue
	if profile_allowed "$profile" "${profiles[@]}" ; then
	    if [[ "$profile" == "$selected" ]] ; then
		printf '* %-22s%s\n' "$profile" "$description"
	    else
		printf '  %-22s%s\n' "$profile" "$description"
	    fi
	fi
    done <<< "$profilesdata"
}

show_name_desc() {
    local type="$1"
    local name="$2"
    local meta="$3"
    if [[ "$type" == "description" ]] ; then
	local description="$(myl_get "$meta" 'description')"
	echo "$name $description"
    else
	echo "$name"
    fi
}

get_all_subprofile_names() {
    local type="$1"
    local profile="$2"
    local profiledir="$3"
    local d
    for d in "$profiledir"/profiles/*; do
        [[ -d "$d" ]] || continue
        if [[ -f "$d/profile.myl" ]]; then
            local profilename=$(basename "$d")
	    profilename="${profilename%$'\r'}"
	    get_all_subprofile_names "$type" "$profile%$profilename" "$d"
	    show_name_desc "$type" "$profile%$profilename" "$d/profile.myl"
	fi
    done
}

get_all_ordered_profile_names() {
    local type="$1"
    local profile="$(resolve_profile_name)"
    declare -A seen=()
    local sc
    for sc in "${PROFILE_SEARCH_ORDER[@]}"; do
        local dir_list="${PROFILE_DIRS[$sc]}" dir=""
        IFS=':' read -ra dirs <<< "$dir_list"
        for dir in "${dirs[@]}"; do
            [[ -d "$dir" ]] || continue
	    local d
            for d in "$dir"/*; do
                [[ -d "$d" ]] || continue
                if [[ -f "$d/profile.myl" ]]; then
                    local profilename=$(basename "$d")
		    profilename="${profilename%$'\r'}"
                    if [[ -z "${seen[$profilename]}" ]]; then
                        seen["$profilename"]=1
			show_name_desc "$type" "$profilename" "$d/profile.myl"
                    fi
		    get_all_subprofile_names "$type" "$profilename" "$d"
                fi
            done
        done
    done
}

handle_profile_command() {
    [[ "$1" =~ ^-h|--help$ ]] && profile_usage
    [[ "$2" =~ ^-h|--help$ ]] && profile_usage

        # 1) consume global flags: -h/--help, --scope
    local scope=""
    local scopearg=""
    while [[ $# -gt 0 ]]; do
	case "$1" in
	    -h|--help)
		tool_usage
		return 0
		;;
	    --scope)
		shift
		scope="$1"
		shift || true
		scopearg=yes
		;;
	    *)
		break
		;;
	esac
    done
    prompt_type="toolset"

    # default scope if none given
    determine_implicit_scope "$prompt_type"
    if [[ "$scopearg" = "yes" && -z "$scope" ]] ; then
	echo "$implicit_scope"
	return
    fi

    local subcmd="${1:-}"
    shift

    # Special default scope handling
    case "$subcmd" in
	list)
	    scope="$implicit_scope"
	    ;;
	*)
	    :
	    ;;
    esac

    if [[ -z "$scope" ]]; then
	scope="session"
    fi

    validate_scope "$scope"
    if [[ "$scope" == "profile" ]] ; then
	die "Scope '$scope' not valid for profile actions."
    fi
    
    local prompt_type="profile"
    
    case "$subcmd" in
	create)
	    local name="$1"
	    if [[ -z "$name" ]] ; then
		die "Name not provided."
	    fi
	    local description="$2"
	    if [[ -z "$description" ]] ; then
		warn "Description not provided."
	    fi
	    local filedir="${SCOPE_DIR[$scope]}/profiles/$name"
	    filedir="${filedir//%/\/profiles\/}"
	    local filepath="$filedir/${prompt_type}.myl"
	    if [[ -e "$filepath" ]] ; then
		die "Profile '$name' already exists."
	    fi
	    # TODO check that sub-profiles exist
	    #
	    mkdir -p "$filedir"
	    myl_add "$filepath" description "$description"
	    notice "Created profile '$name' with description '$description'."
	    ;;

	list|ls)
	    init_profile_search_dirs
	    list_profiles
	    ;;

	delete)
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
			local ses_meta="$ses_dir/session.myl"
			if [[ -f "$ses_meta" ]]; then
			    local ses_profile="$(myl_get "$ses_meta" 'profile')"
			    if [[ "$ses_profile" == "$name" ]]; then
				die "Cannot delete profile '$name' because session '$(basename "$ses_dir")' is currently using it."
			    fi
			fi
		    done
		fi
	    fi
	    local filedir="${SCOPE_DIR[$scope]}/profiles/$name"
	    filedir="${filedir//%/\/profiles\/}"
	    local subnames="$(get_all_subprofile_names "file" "$name" "$filedir")"
	    if [[ -n "$subnames" ]] ; then
		error "Cannot delete a profile with sub-profiles:"
		printf '%s\n' "$subnames" >&2
		exit 1
	    fi
	    rm -Rf "$filedir"
	    notice "Deleted profile '$name'"
	    #
            ;;

	"")
	    local profile="$(resolve_profile_name)"
	    if [[ ! -n "$profile" ]] ; then
		profile="-"
	    fi
	    echo "${profile}"
	    ;;	    

	*)
	    die "Unknown profile command: $subcmd"
	    ;;
    esac
}
