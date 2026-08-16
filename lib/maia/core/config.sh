#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

config_usage() {
    cat <<'EOF'
USAGE

  maia config [options] <command> [<name>] [<value>]
  maia config [options] [<name>] [<value>]
  maia config

Manage configuration settings for the MAIA tool.

COMMANDS

  list|ls
    List all available configuration keys.

  get [<name>]
    Display the effective merged setting for each key, or only <name> if given.
    Honors the --scope option for restricting to a particular layer.
    Ignores --all and --cost.

  set <name> <value>
    Set the configuration key <name> to <value> in the specified scope.
    Ignores --all and --cost.
    Use --effective to target the highest-priority scope where the key is currently defined.

  unset <name>
    Remove <name> from the specified scope, reverting to a lower-level setting
    or default.
    Ignores --all and --cost.
    Use --effective to target the highest-priority scope where the key is currently defined.

  When no command is given it defaults to set when both name and value is provided and
  defaults to get if only name is provided.

OPTIONS

  --scope <scope>
    Specify the configuration layer: session, workspace, home (default), user, or system.

  --effective
    For set/unset: target the highest-priority scope where the key is currently defined.
    If the key is not present in any scope, behaves like a normal write (home by default).

  --all
    Show all configuration items.

  --cost
    Show only cost related configuration items.

  --file
    Show only file handling mode related configuration items.

  -h, --help
    Show this help message and exit.

EXAMPLES

  maia config list
    List all available configuration keys, except cost related.

  maia config --all list
    List all available configuration keys.

  maia config --cost list
    List all cost related configuration keys.

  maia config scope model
    Show the scope for the "model" configuration key.

  maia config --scope workspace get
    Show configuration for the workspace scope.

  maia config temperature 0.5
    Set temperature to 0.5 in the default scope.

  maia config --scope user unset stream
    Unset the "stream" key in the user scope.

  maia config
    Show non-cost related configuration.

  maia config --all
    Show all configuration.

NOTES

  The configuration scopes follow a priority order from most specific to least:
    session, workspace, home, user, system, default.

  The default write scope is home.

  When no command is given it defaults to maia config show to show the
  current active configuration.

  Cost configuration is in \$/1M tokens

  For the configuration key 'default_session_filesets', you may set it using a
  simple comma-separated list instead of JSON. For example:
    maia config set default_session_filesets default,test1
  This will be converted automatically to a JSON array.
EOF
    exit 0
}

FILTER_CONFIG_KEYS=()

# Helper: find the highest-priority scope (most specific) that currently contains a key.
# Echoes scope name or empty string if not present in any on-disk scope.
find_highest_scope_with_key() {
    local name="$1"
    local s
    for s in "${SCOPE_ORDER[@]}"; do
	[[ "$s" == "default" ]] && continue
	local file=$(content_of_file_in_scope "$s" "config.json")
	if [[ -n "$file" && -f "$file" ]] && jq -e --arg k "$name" '.[$k]' "$file" >/dev/null 2>&1; then
	    echo "$s"
	    return 0
	fi
    done
    echo ""
    return 1
}

# Helper: return numeric index of a scope in SCOPE_ORDER (0 = highest priority).
scope_index() {
    local scope="$1"
    local i
    for i in "${!SCOPE_ORDER[@]}"; do
	if [[ "${SCOPE_ORDER[$i]}" == "$scope" ]]; then
	    echo "$i"
	    return 0
	fi
    done
    # Unrecognized scope -> large index
    echo 999
    return 1
}

# Helper: returns success (0) if scope $1 is higher priority (more specific) than scope $2
is_scope_higher() {
    local a="$1" b="$2"
    local ia ib
    ia=$(scope_index "$a")
    ib=$(scope_index "$b")
    (( ia < ib ))
}

handle_config_command() {
    # If requesting help
    [[ "$1" =~ ^-h|--help$ ]] && config_usage
    [[ "$2" =~ ^-h|--help$ ]] && config_usage
    local filter="normal"
    
    # We'll track whether user provided --scope. Writes default to "home".
    local scope=""
    local scope_given=0
    local write_scope="home"
    local view_scope=""
    local effective_flag=0

    # Parse optional flags
    while [[ $# -gt 0 ]]; do
	case "$1" in
	    --scope)
		shift
		scope="$1"
		scope_given=1
		shift
		;;
            --effective)
                effective_flag=1
                shift
                ;;
	    --all)
                filter="all"
                shift
                ;;
            --cost)
                filter="cost"
                shift
                ;;
            --file)
                filter="file"
                shift
                ;;
	    *)
                # For now, treat as normal config keys or subcommands
                break
                ;;
	esac
    done

    if [[ "$scope_given" -eq 1 && "$effective_flag" -eq 1 ]]; then
        die "Cannot combine --scope and --effective"
    fi

    # Decide view vs write scopes:
    # - If user provided --scope, both view and write should use that scope.
    # - If not, viewing defaults to session (merged to session) while writing defaults to home.
    if [[ "$scope_given" -eq 1 ]]; then
        write_scope="$scope"
        view_scope="$scope"
    else
        write_scope="home"
        view_scope="session"
    fi

    local key
    for key in ${CONFIG_KEYS[*]}; do
	case "$filter" in
            normal)
		if [[ "$key" == cost_* ]]; then
		    # Exclude keys starting with cost_
		    continue
		fi
                if [[ "$key" == file_handling_mode_* ]]; then
                    # Include only file_handling_mode keys
		    continue
                fi
		;;
            cost)
                if [[ "$key" != cost_* ]]; then
                    # Include only cost_ keys
		    continue
                fi
                ;;
            file)
                if [[ "$key" != file_handling_mode_* ]]; then
                    # Include only file_handling_mode keys
		    continue
                fi
                ;;
            all)
                ;;
        esac 
        FILTER_CONFIG_KEYS+=( "$key" )
    done
    
    local cmd="$1"
    case "$cmd" in
	list)
	    list_config_keys
	    ;;

	show)
	    shift
	    # Optional name
	    local name="$1"
	    show_config "$name" "$filter" "$view_scope"
	    ;;

	get)
	    shift
	    # Optional name
	    local name=""
	    if [[ -n "$1" ]]; then
		name=$1
		shift
	    fi
	    if [ -z "$name" ] ; then
		# Show merged config according to view scope (defaults to session when --scope not given)
		get_config "" "$view_scope"
		return
	    fi
	    if [[ "$name" == --* ]]; then
		die "Invalid configuration key name '$name'. It cannot start with '--'."
	    fi
	    get_config "$name" "$view_scope"
	    ;;

	set)
	    shift
	    local name=$1
	    local value=$2
	    if [[ -z "$name" || -z "$value" ]]; then
		if [[ -z "$name" ]] ; then
		    error "Name missing.";
		fi
		if [[ -z "$value" ]] ; then
		    error "Value missing.";
		fi
		config_usage
		exit 1
	    fi
	    if [[ "$name" == --* ]]; then
		die "Invalid configuration key name '$name'. It cannot start with '--'."
	    fi
	    # Special handling for default_session_filesets to convert CSV to JSON array
	    if [[ "$name" == "default_session_filesets" ]]; then
		IFS=',' read -r -a fs_array <<< "$value"
		value=$(printf '%s\n' "${fs_array[@]}" | jq -R . | jq -s .)
	    fi

	    # Determine effective target scope for set
	    local target_scope="$write_scope"
	    if [[ "$effective_flag" -eq 1 ]]; then
		local highest
		highest=$(find_highest_scope_with_key "$name")
		if [[ -n "$highest" ]]; then
		    target_scope="$highest"
		else
		    target_scope="$write_scope"
		fi
	    fi

	    # If there exists a higher-priority scope that defines this key than the target,
	    # warn the user that changing target_scope will not affect the effective value.
	    local highest_now
	    highest_now=$(find_highest_scope_with_key "$name")
	    if [[ -n "$highest_now" ]] && is_scope_higher "$highest_now" "$target_scope" ; then
		warn "Note: Effective value for '$name' comes from scope '$highest_now'. Changing '$name' in scope '$target_scope' will not affect the effective value."
	    fi

	    set_config "$name" "$value" "$target_scope"
	    ;;

	unset)
	    shift
	    local name=$1
	    if [[ -z "$name" ]]; then
		if [[ -z "$name" ]] ; then
		    error "Name missing.";
		fi
		config_usage
		exit 1
	    fi

	    # Determine effective target scope for unset
	    local target_scope="$write_scope"
	    if [[ "$effective_flag" -eq 1 ]]; then
		local highest
		highest=$(find_highest_scope_with_key "$name")
		if [[ -n "$highest" ]]; then
		    target_scope="$highest"
		else
		    target_scope="$write_scope"
		fi
	    fi

	    # If there exists a higher-priority scope that defines this key than the target,
	    # warn the user that unsetting target_scope will not affect the effective value.
	    local highest_now
	    highest_now=$(find_highest_scope_with_key "$name")
	    if [[ -n "$highest_now" ]] && is_scope_higher "$highest_now" "$target_scope" ; then
		warn "Note: Effective value for '$name' comes from scope '$highest_now'. Unsetting '$name' in scope '$target_scope' will not affect the effective value."
	    fi

	    unset_config "$name" "$target_scope"
	    ;;

	"")
	    show_config "" "$filter" "$view_scope"
	    ;;

	*)
	    local name="$1"
	    local value="$2"
	    if [[ -z "$name" && -z "$value" ]]; then
		show_config # This cannot happen since we have "" above
	    elif [[ -n "$name" && -z "$value" ]] ; then
		debug "Get config"
		get_config "$name" "$view_scope"
	    else
		debug "Set config '$name' '$value' '$write_scope'"
		# Special handling for default_session_filesets to convert CSV to JSON array
		if [[ "$name" == "default_session_filesets" ]]; then
		    IFS=',' read -r -a fs_array <<< "$value"
		    value=$(printf '%s\n' "${fs_array[@]}" | jq -R . | jq -s .)
		fi

		# Determine target scope (respect --effective)
		local target_scope="$write_scope"
		if [[ "$effective_flag" -eq 1 ]]; then
		    local highest
		    highest=$(find_highest_scope_with_key "$name")
		    if [[ -n "$highest" ]]; then
			target_scope="$highest"
		    else
			target_scope="$write_scope"
		    fi
		fi

		# Warn if a higher-priority scope currently defines the key
		local highest_now
		highest_now=$(find_highest_scope_with_key "$name")
		if [[ -n "$highest_now" ]] && is_scope_higher "$highest_now" "$target_scope" ; then
		    warn "Note: Effective value for '$name' comes from scope '$highest_now'. Changing '$name' in scope '$target_scope' will not affect the effective value."
		fi

		set_config "$name" "$value" "$target_scope"
	    fi
	    ;;
    esac
}

# List available configuration keys
list_config_keys() {
    for k in "${FILTER_CONFIG_KEYS[@]}"; do
	echo "$k"
    done
}

# Show effective scope for keys (name optional)
show_config() {
    local name="$1"
    local filter="$2" # Only used to determine environment variables to be shown or not
    local view_scope="${3:-session}"
    printf "%-30s %-10s %s\n" "CONFIG NAME" "SCOPE" "VALUE"
    echo "----------------------------------------------------------------------------"
    local merged=$(load_merged_config "$view_scope")
    local keys
    if [[ -n "$name" ]]; then
        keys=($name)
    else
        # Sort FILTER_CONFIG_KEYS alphabetically
        IFS=$'\n' keys=($(sort <<<"${FILTER_CONFIG_KEYS[*]}"))
        unset IFS
    fi
    local key
    for key in "${keys[@]}"; do
	local found="default"
	# If view_scope is "default", do not inspect on-disk files; everything is default.
	if [[ "$view_scope" != "default" ]]; then
	    local start=false
	    local s
	    # Iterate scopes in priority order but only consider scopes from view_scope
	    # downward (i.e., less specific). This prevents reporting a defining scope
	    # that is more specific than the requested view scope.
	    for s in "${SCOPE_ORDER[@]}"; do
		if [[ "$s" == "$view_scope" ]]; then
		    start=true
		fi
		[[ "$start" != true ]] && continue
		local file=$(content_of_file_in_scope "$s" "config.json")
		if [[ -n "$file" && -f "$file" ]] && jq -e --arg k "$key" '.[$k]' "$file" >/dev/null; then
		    found=$s
		    break
		fi
	    done
	fi
	local value="$(echo "$merged" | jq -c --arg key "$key" '.[$key]')"
	printf "%-30s %-10s %s\n" "$key" "$found" "$value"
    done
    echo
    printf "%-30s %s\n" "ENVIRONMENT NAME" "VALUE"
    echo "----------------------------------------------------------------------------"
    # Print environment variables if set, masking sensitive ones
    local env_vars=(
        "MAIA_EDITOR"
        "MAIA_SESSION"
        "EDITOR"
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "AWS_SESSION_TOKEN"
        "OPENAI_API_KEY"
    )
    local var
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var}" || "$filter" == "all" ]]; then
            local display_value="${!var}"
            case "$var" in
                AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|OPENAI_API_KEY)
                    display_value="********************************"
                    ;;
		*)
		    display_value="\"$display_value\""
		    ;;
            esac
            printf "%-30s %s\n" "$var" "$display_value"
        fi
    done
}

# Determine the path to config.json for a given scope using SCOPE_DIRS
config_file_for_scope() {
    local scope=$1
    # The pseudo‐scope “default” has no on-disk file
    if [[ "$scope" == "default" ]]; then
	echo ""
	return
    fi
    # Look up the directory for this scope
    local dir=${SCOPE_DIRS[$scope]}
    if [[ -z "$dir" ]]; then
	echo "Unknown scope: $scope" >&2
	exit 1
    fi
    echo "$dir/config.json"
}

config_exists() {
    local name="$1"
    local found="no"
    # Allow keys starting with cost_input_ or cost_output_ or file_handling_mode_
    if [[ "$name" == cost_input_* || "$name" == cost_output_* || "$name" == file_handling_mode_* ]]; then
        found="yes"
    else
	local key
        for key in ${CONFIG_KEYS[*]}; do
            if [[ "$name" == "$key" ]] ; then
                found="yes"
            fi
        done
    fi
    if [[ "$found" == "no" ]] ; then
        die "Configuration '$name' does not exist."
    fi
}

# Get effective merged setting for name or all
get_config() {
    local name="$1"
    if [[ -n "$name" ]] ; then
	config_exists "$name"
    fi
    local scope="${2:-session}"
    local merged=$(load_merged_config "$scope")
    if [[ -n "$name" ]]; then
	echo "$merged" | jq -r --arg key "$name" '.[$key]'
    else
	echo "$merged" | jq .
    fi
}

# Set config name to value in given scope
set_config() {
    local name=$1
    config_exists "$name"
    local value=$2
    local scope=$3
    local file; file=$(config_file_for_scope "$scope")
    mkdir -p "$(dirname "$file")"

    # Detect if value looks like JSON (starts with [ or {)
    if [[ "$value" =~ ^\s*[\[\{] ]]; then
        # Assume valid JSON, use directly
        local json_val="$value"
    else
        # Otherwise convert to JSON string literal
        local json_val=$(coerce_to_json "$value")
    fi

    if [[ -f "$file" ]]; then
        local tmp; tmp=$(mktemp)
        jq --arg key "$name" --argjson val "$json_val" '.[$key]=$val' "$file" > "$tmp" && mv "$tmp" "$file"
    else
        echo "{ \"$name\": $json_val }" > "$file"
    fi
}

# Unset a configuration key in the given scope
unset_config() {
    local name=$1
    config_exists "$name"
    local scope=$2

    # Determine the path to the scope’s config.json
    local file; file=$(config_file_for_scope "$scope")

    # If there's no config file at all, nothing to unset
    if [[ ! -e "$file" ]]; then
	warn "No configuration file for scope '$scope' (nothing to unset)"
	return 0
    fi

    # If the key isn't present in that file, nothing to remove
    if ! jq -e --arg k "$name" 'has($k)' "$file" >/dev/null; then
	warn "Key '$name' not set in scope '$scope' (nothing to unset)"
	return 0
    fi

    # Otherwise delete the key and overwrite the file
    local tmp; tmp=$(mktemp)
    jq --arg key "$name" 'del(.[$key])' "$file" > "$tmp" \
	&& mv "$tmp" "$file" \
	&& info "Unset '$name' in scope '$scope'"
}
