#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

update_usage() {
    cat <<'EOF'
USAGE

  maia update [options] <command>
    Run one of the sub-commands.
  maia update
    Upgrade and refresh.

Update data structures to the latest software and refresh skills and tools.

COMMANDS

  upgrade
    Update the data structures

  refresh
    Refresh skills and tools.

OPTIONS

  -h, --help
    Show this help message and exit.

EOF
    exit 0
}

json_to_myl(){
    local jsonfile="$1"
    local mylfile="$2"
    local tmpfile="${mylfile}.tmp.$$"

    # Change metadata is a JSON object whose values are represented as
    # scalar MYL values, JSON arrays/objects, or indented multiline text.
    # Write to a temporary file so a malformed input never leaves a partial
    # MYL file behind.
    if ! jq -r '
      if type != "object" then
        error("change metadata must be a JSON object")
      else
        to_entries[] |
        if (.value | type) == "string" and (.value | contains("\n")) then
          "\\(.key):\\n  " + (.value | gsub("\\n"; "\\n  "))
        else
          "\\(.key): \\(.value)"
        end
      end
    ' "$jsonfile" > "$tmpfile"; then
        rm -f "$tmpfile"
        return 1
    fi

    mv -- "$tmpfile" "$mylfile"
}

convert_change_json_files() {
    convert_x_json_files "change" '*/changes/*/*.json'
}

convert_config_json_files() {
    convert_x_json_files "change" '*/config.json'
}

convert_x_json_files() {
    local type="$1"
    shift
    local maia_home="$(resolve_home_dir)"
    local jsonfile mylfile converted=0 skipped=0 failed=0

    [[ -d "$maia_home" ]] || {
        notice "MAIA home '$maia_home' does not exist; nothing to upgrade."
        return 0
    }

    # Change files live below .../changes/<session>.  Restricting the search
    # to this path is important: history.json and other API/config JSON files
    # must remain JSON.
    while IFS= read -r -d '' jsonfile; do
        mylfile="${jsonfile%.json}.myl"

        if [[ -e "$mylfile" ]]; then
            info "Skipping '$jsonfile': '$mylfile' already exists."
            skipped=$((skipped + 1))
            continue
        fi

        if ! json_to_myl "$jsonfile" "$mylfile"; then
            error "Unable to convert $type metadata '$jsonfile'."
            failed=$((failed + 1))
            continue
        fi

        # Remove the source only after the MYL file was written successfully.
        #rm -- "$jsonfile"
        info "Converted $type metadata '$jsonfile' to '$mylfile'."
        converted=$((converted + 1))
    done < <(find "$maia_home" -path "$@" -type f -print0)

    notice "Change metadata upgrade complete: $converted converted, $skipped skipped, $failed failed."
    (( failed == 0 ))
}

handle_update_command() {
    # help flags
    [[ "$1" =~ ^-h|--help$ ]] && update_usage
    [[ "$2" =~ ^-h|--help$ ]] && update_usage

    local cmd="${1:-upgrade}"
    shift || true

    case "$cmd" in
	"")
	    handle_update_command upgrade
	    handle_update_command refresh
	    ;;
        upgrade)
            convert_change_json_files
            convert_config_json_files
            ;;
        refresh)
            :
            ;;
        check)
            :
            ;;
        *)
            die "Unknown update command '$cmd'."
            ;;
    esac
}
