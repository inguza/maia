#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

workspace_usage() {
    cat <<'EOF'
USAGE

  maia workspace <command> [options]

Manage workspace manifests and their filesets.

COMMANDS

  use [<name>]
    Set or show the current workspace name.

  select - an alias of use

  unuse
    No longer use any session.

  unselect - an alias of unuse

  create [<name>] [--use|--nouse] [--path <path>] [--filesets <json-array>] [--default-session-filesets <json-array>]
    Create a new workspace manifest. 
    If <name> is omitted, the default is:
      • "default" if <workspace_path>/.maia matches MAIA_HOME
      • basename("<workspace_path>") otherwise.

  set [<name>] [--use|--nouse] [--path <path>] [--filesets <json-array>] [--default-session-filesets <json-array>]
    Change the workspace properties.

  list|ls
    List all available workspaces.

  show [options] [<name>]
    Display the manifest of the specified (or current) workspace.
    Options are:
      --raw|--json  Output in json format.

  edit [<name>] [--use|--nouse]
    Open the workspace meta data file in $EDITOR.

  clear [--fileset] [--system] [<name>]
    Reset the manifest (keep "name" and "path").

  delete [--force] <name>
    Delete the specified workspace (cannot delete the current one).

OPTIONS

  -h, --help
    Show this help message for the "workspace" subcommand.

  --use (aliased as --select as well)
    Override configuration parameter auto_use_at_create or auto_use_at_set respectively
    so that the workspace is used after creation/set.

  --nouse (aliased as --unselect as well)
    Override configuration parameter auto_use_at_create or auto_use_at_set respectively
    so that the workspace is not used after creation/set.

  --path <directory>
    Specify the filesystem path for the workspace.

  --filesets <json-array> (create and set)
    Specify the list of filesets in the workspace as a JSON array of strings.
    Example: '["default", "tests", "docs"]'

  --default-session-filesets <json-array> (create and set)
    Set the default session filesets as a JSON array of strings.
    Supports the special marker "__WORKSPACE_FILESETS__" to represent all
    current workspace filesets.
    Example: '["__WORKSPACE_FILESETS__", "extra_fileset"]'
    If omitted during workspace creation, defaults to ["__WORKSPACE_FILESETS__"].

  --fileset (only with clear)
    Remove all filesets and recreate default fileset.

  --system (only with clear)
    Delete system.txt in the workspace folder.

EXAMPLES

    maia workspace list
      List all available workspaces.

    maia workspace create myworkspace --path /path/to/project
      Create a workspace named "myworkspace" with the specified path.

    maia workspace use myworkspace
      Set "myworkspace" as the current workspace.

NOTES

  Workspace manifests maintain metadata about project paths and associated filesets.

  If <name> is omitted, the default is the current workspace (except for create).  

EOF
    exit 0
}

# parse_workspace_options [<args>…]
# Returns:
#   PARSED_PATH        — string or empty
#   PARSED_FILESETS    — JSON array string (or empty)
# Leaves leftovers in REMAINING_ARGS[@]
parse_workspace_options() {
    PARSED_PATH=""
    PARSED_FILESETS=""
    REMAINING_ARGS=()
    # Do NOT initialize USE here; will be set before call

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                shift
                [[ -n "$1" ]] || { echo "Error: --path requires a directory." >&2; workspace_usage; }
                PARSED_PATH="$(cd "$1" && pwd -P)"; shift
                ;;
            --filesets)
                shift
                [[ -n "$1" ]] || { echo "Error: --filesets requires a comma-separated list." >&2; workspace_usage; }
                # Split on commas into an array, then JSONify
                IFS=',' read -r -a _arr <<< "$1"
                # wrap each in JSON string
                local _jq=()
                for fs in "${_arr[@]}"; do
                    _jq+=( "\"$fs\"" )
                done
                PARSED_FILESETS="[${_jq[*]}]"
                shift
                ;;
	    --use|--unselect)
		shift
		USE="true"
		;;
	    --nouse|--unselect)
		shift
		USE="false"
		;;
            -*)
                echo "Error: Unknown option '$1'" >&2
                workspace_usage
                ;;
            *)
                REMAINING_ARGS+=( "$1" )
                shift
                ;;
        esac
    done
}

handle_workspace_command() {
    [[ "$1" =~ ^-h|--help$ ]] && workspace_usage
    [[ "$2" =~ ^-h|--help$ ]] && workspace_usage

    local cmd="${1:-}"

    local data_dir project_dir project_name

    case "$cmd" in
	use|select)
	    shift
	    handle_x_use "workspace" "$1" # Handles optional name
	    ;;

	unuse|unselect)
	    shift
	    handle_x_unuse "workspace"
	    ;;

	create)
	    shift
	    local USE=$(jq -r '.auto_use_at_create // true' <<< "$_cfg")
	    # 1) Parse flags into PARSED_PATH / PARSED_FILESETS
	    parse_workspace_options "$@"
	    # 2) Determine name and path
	    #    First leftover arg is the workspace name, else derive from CWD
	    local name="${REMAINING_ARGS[0]:-$(basename "$PWD")}"
	    local path="${PARSED_PATH:-$PWD}"
	    # 3) Prepare directories & ensure none exists
	    local ws_dir="$(resolve_workspace_path "$name")"
	    local meta="$(resolve_workspace_meta "$name")"
	    [[ ! -e "$meta" ]] || die "Workspace '$name' already exists"
	    mkdir -p "$ws_dir/changes"
	    # 4) Compute arrays (JSON strings)
	    local filesets_json="${PARSED_FILESETS:-[\"default\"]}"
	    # 6) Materialize each fileset as an empty file
	    local fs
	    # Use jq to extract names robustly
	    while IFS= read -r fs; do
		: > "$ws_dir/${fs}.fileset"
	    done < <(jq -r '.[]' <<<"$filesets_json")
	    # 7) Write workspace.json with all four keys
	    write_workspace_meta \
		"$ws_dir" \
		"$path" \
		"$filesets_json"
	    notice "Created workspace '$name' for '$path' with filesets: $(jq -r '.[]|@sh'<<<"$filesets_json")"
	    if [[ "$USE" == "true" ]] ; then
		handle_x_use "workspace" "$name"
	    fi
	    ;;

	set)
            shift
	    local USE=$(jq -r '.auto_use_at_set // true' <<< "$_cfg")
            parse_workspace_options "$@"
            # 1) Determine workspace name (first non-flag) or fallback
            local name="${REMAINING_ARGS[0]:-$(resolve_workspace_name)}"
	    local ws_dir=$(resolve_workspace_path "$name")
            local meta=$(resolve_workspace_meta  "$name")
            # 2) Ensure workspace exists
            [[ -f "$meta" ]] || die "Workspace '$name' does not exist"
            # 3) Load current values
            local current_path="$(resolve_workspace_root "$name")"
            local current_filesets_json="$(resolve_workspace_filesets_json "$name")"
            # 4) Parse flags (sets: PARSED_PATH, PARSED_FILESETS
	    # 5) Compute new values, falling back to current if omitted
            local new_path="${PARSED_PATH:-$current_path}"
            local filesets_json="${PARSED_FILESETS:-$current_filesets_json}"
            # Build JSON array of existing fileset names on disk
            mapfile -t EXISTING_FS < <(resolve_all_workspace_filesets "$name")
            local existing_json=$(printf '%s\n' "${EXISTING_FS[@]}" \
				      | jq -R . | jq -s .)
            # 6a) Validate that any supplied --filesets are a subset of what exists
            if [[ -n "$PARSED_FILESETS" ]]; then
		# TODO: We should probably auto-create them instead
		validate_subset \
                    "$filesets_json" \
                    "$existing_json" \
                    "filesets"
            fi
            # 7) Write out updated workspace.json
            write_workspace_meta \
		"$ws_dir" \
		"$new_path" \
		"$filesets_json"
	    info "Updated workspace '$name'"
	    if [[ "$USE" == "true" ]] ; then
		handle_x_use --no-use-notice "workspace" "$name"
	    fi
            ;;
	
	edit)
            shift
	    local USE=$(jq -r '.auto_use_at_set // true' <<< "$_cfg")
            parse_workspace_options "$@"
            local name="${REMAINING_ARGS[0]:-$(resolve_workspace_name)}"
            handle_x_edit "workspace" "workspace" "$name" # Handles optional name
	    if [[ "$USE" == "true" ]] ; then
		handle_x_use --no-use-notice "workspace" "$name"
	    fi
            ;;

	list|ls)
	    shift
	    handle_x_list workspace
	    ;;

	show)
            shift
	    local raw_output=0
	    while [[ $# -gt 0 ]]; do
		case "$1" in
		    --raw|--json)
			raw_output=1
			shift
			;;
		    *)
			break
			;;
		esac
	    done
            # If no name given, use the active workspace
            local name="${1:-$(resolve_workspace_name)}"
            # Resolve metadata path
            local meta="$(resolve_workspace_meta "$name")"
            # Verify it exists
            [[ -f "$meta" ]] || die "Workspace '$name' does not exist"
	    local workspace_json=$(jq --arg name "$name" '. + {name: $name}' "$meta")
	    if (( raw_output )); then
		echo "$workspace_json" | jq .
	    else
		local path=$(jq -r '.path // empty' <<< "$workspace_json")
		local filesets=$(jq -r '.filesets // empty | @json' <<< "$workspace_json")
		# Get current session name and its expanded filesets
		local session_name=$(resolve_session_name)
		# Convert session expanded filesets to a map for quick lookup
		declare -A session_fs_map=()
		local session_expanded_filesets=$(get_session_expanded_filesets "$session_name")
		local fs
		while IFS= read -r fs; do
		    session_fs_map["$fs"]=1
		done < <(jq -r '.[]' <<< "$session_expanded_filesets")

		echo "Workspace: $name"
		if [[ -n "$path" ]]; then
		    echo "Path:      $path"
		else
		    echo "Path:      (none)"
		fi
		if [[ "$filesets" != "null" && "$filesets" != "[]" ]]; then
		    echo "Filesets:"
		    jq -r '.filesets[]' <<< "$workspace_json" | while IFS= read -r fs; do
			if [[ -n "${session_fs_map[$fs]}" ]]; then
			    echo " *+ $fs"
			else
			    echo "  + $fs (not used by session)"
			fi
		    done
		else
		    echo "Filesets: (none)"
		fi
	    fi
            ;;

	clear)
            shift
            local name="${1:-$(resolve_workspace_name)}"
            # Read the existing path
	    local ws_dir="$(resolve_workspace_path "$name")"
	    if [[ ! -d "$ws_dir" ]]; then
		die "Workspace '$name' does not exist"
	    fi
            local ws_path="$(resolve_workspace_root "$name")"
            # Rewrite metadata with only path and empty defaults
	    write_workspace_meta "$ws_dir" "$ws_path" '[]'
            info "Cleared workspace '${name:-$(resolve_workspace_name)}'"
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
	    [[ -n "$name" ]] || die "Workspace name required."
	    if [[ "$FORCE" != true ]]; then
		# 1) Prevent deleting the active workspace
		local active_ws=$(resolve_workspace_name)
		if [[ "$name" == "$active_ws" ]]; then
		    die "Cannot delete the active workspace '$name'. Switch to a different workspace before deleting."
		fi
		# 2) Check if any session uses this workspace
		local sessions_dir="$(resolve_session_base)"
		if [[ -d "$sessions_dir" ]]; then
		    shopt -s nullglob
		    for ses_dir in "$sessions_dir"/*; do
			[[ -d "$ses_dir" ]] || continue
			local ses_meta="$ses_dir/session.json"
			if [[ -f "$ses_meta" ]]; then
			    local ses_ws=$(jq -r '.workspace // empty' "$ses_meta")
			    if [[ "$ses_ws" == "$name" ]]; then
				die "Cannot delete workspace '$name' because session '$(basename "$ses_dir")' is currently using it."
			    fi
			fi
		    done
		fi
	    fi
	    # Now all checks are in place, now you can delete
	    handle_x_delete "workspace" "$1" # Handles optional name
            ;;

	"")
	    handle_workspace_command use
	    ;;

	*)
	    die "Unknown workspace command: $cmd"
	    ;;
    esac
}
