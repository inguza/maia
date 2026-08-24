#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

parse_usage() {
    cat <<'EOF'
USAGE

  aia parse [<range>] [--force] [<default-filename> ...]

Extract the latest assistant reply(s) from the current session’s history,
write them into change files under the workspace’s changes/ directory, and
invoke the change parser.

OPTIONS

  --force
    Re-parse even if the change files already exist.

  --auto-parse
    Only parse if obvious full or patch file changes are detected (skip generic fenced snippets).

  --whole
    Indicate that the whole output is a snippet without anything around it.

  -h, --help
    Show this help message and exit.

  <range>
    Specify which assistant messages to parse, e.g., 'last', 'last-3', '0:5', etc.
    Defaults to 'last' if omitted.

  <default-filename> ...
    One or more filenames to assign to snippet blocks that do not have explicit
    filenames in the assistant output. These are assigned in order to snippet blocks
    missing filenames during parsing.

    Each default filename must be unique and is relative to the workspace root directory.

    Example:

      aia parse last --force src/foo.c src/bar.c

    This command parses the last assistant reply, forcing re-parse, and assigns
    'src/foo.c' to the first snippet without a filename, 'src/bar.c' to the second,
    and so on.

NOTES

  - Default filenames are only applied to snippet blocks lacking explicit filenames or
    those that cannot be determined heuristically.

  - If more snippet blocks require filenames than the number of default filenames
    provided, the remaining snippets will be treated as unnamed snippets.

  - It is recommended to first run 'aia parse' without default filenames to identify
    which snippets require filename assignments, then re-run with appropriate defaults.

  Deprecation note!
  =================

  The output parsing has been replaced with the file-write and file-change functionality.
  Once that functionality has been more throughly tested with all interface providers then
  this parse functionality is likely going to be removed.

  Broken parse functionality may be removed before this.

EOF
    exit 0
}

handle_parse_command() {
    [[ "$1" =~ ^-h|--help$ ]] && parse_usage

    # 1) bootstrap session & workspace
    ensure_session_exists
    local session_name="$(resolve_session_name)"
    local history_file="$(resolve_history_meta)"
    local ws_path="$(resolve_workspace_path)"
    local ws_changes="${ws_path}/changes/${session_name}"

    # 2) parse flags and collect default filenames
    local range="" force=0 auto_parse_flag="" auto_parse=0
    local -a default_filenames=()
    local extra=""
    for arg in "$@"; do
        case "$arg" in
            --force)
		force=1
		;;
            --auto-parse)
		auto_parse_flag="--auto-parse"
		auto_parse=1
		;;
            --whole)
		extra=" --whole "
		;;
            last|last-*)
		range="$arg"
		;;
            *-[0-9]*|[0-9]*-[0-9]*|[0-9]*-)
		range="$arg"
		;;
            *)
		default_filenames+=("$arg")
	       ;;
        esac
    done
    if [[ -z "${ws_path}" ]] ; then
	if [[ $auto_parse -eq 1 ]] ; then
	    return
	else
	    die "No workspace defined."
	fi
    fi
    mkdir -p "$ws_changes"

    [[ -z "$range" ]] && range="last"
    slice=$(range_defaults "$range")

    # 3) extract assistant replies in that slice
    mapfile -t entries < <(
        jq -c "
            .[$slice]
            | (if type==\"array\" then . else [.] end)
            | to_entries[]
            | select(.value.role==\"assistant\")
            " "$history_file"
    )

    local default_filenames_file="$(mktemp)"
    printf '%s\n' "${default_filenames[@]}" > "$default_filenames_file"
    # 4) for each entry, write & invoke parser with --session and pass default filenames and --auto-parse if set
    for entry in "${entries[@]}"; do
        msg_json=$(jq -c .value <<<"$entry")
        entry_ts=$(jq -r '.timestamp // empty' <<<"$msg_json")
        local content=$(jq -r .content <<<"$msg_json")
        local shaid=$(printf '%s' "$content" | sha256sum | cut -c1-8)
        local id=$(jq -r '.id' <<<"$msg_json")
        local outfile="$ws_changes/${entry_ts}-${id}.txt"
        if (( force )); then
            # Remove old files to allow new ones. Remove to ensure consistency.
            rm -f "$ws_changes/${entry_ts}-${id}"* 2>/dev/null || true
        fi
        if [[ ! -f "$outfile" ]]; then
	    local tab_width=$(jq -r '.tab_width' <<<"$_cfg")
	    local allowed_files=$(jq -r '.splice_allowed_files' <<<"$_cfg")
            printf '%s' "$content" > "$outfile"
            "$MAIA_CORE_LIB_DIR/parse.pl" "parse" $auto_parse_flag --loglevel "$TERM_LOGLEVEL" \
				--default-filenames-file "$default_filenames_file" \
				--tab-width "$tab_width" --allowed-files "$allowed_files" \
				$extra \
				"$outfile" "$(resolve_workspace_root)"
            # Remove .txt file if no change files created for this id
            local json_files=( "$ws_changes/${entry_ts}-${id}"*.json )
            if [[ ${#json_files[@]} -eq 0 ]]; then
                rm -f "$outfile"
		if [[ $auto_parse -eq 1 ]] ; then
                    rm -f "${outfile}.orig"
		fi
            fi
        else
            notice "[SKIP] $outfile already exists"
        fi
    done
    rm -f "$default_filenames_file"
}
