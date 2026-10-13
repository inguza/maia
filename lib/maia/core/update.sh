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

The refresh operation searches the session, profile, workspace, and home
scopes for toolset.txt and skillset.txt/skillsetcontext.txt files and refreshes
each file that is found.

COMMANDS

  upgrade
    Update the data structures

  refresh
    Refresh all found tool and skill definition files in the session, profile,
    workspace, and home scopes.

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
        if (.value | type) == "array" then
          "\(.key): \(.value | map(tostring) | join(" "))"
        elif (.value | type) == "string" and (.value | contains("\n")) then
          "\(.key):\\n  " + (.value | gsub("\\n"; "\\n  "))
        else
          "\(.key): \(.value)"
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
    convert_x_json_files "config" '*/config.json'
}

convert_session_json_files() {
    convert_x_json_files "session" '*/session.json'
}

convert_profile_json_files() {
    convert_x_json_files "profile" '*/profile.json'
}

convert_workspace_json_files() {
    convert_x_json_files "workspace" '*/workspace.json'
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

    local filelist="$(mktemp)" || die "Unable to create temporary file."

    if ! find "$maia_home" -path "$1" -type f -print0 > "$filelist"; then
        rm -f -- "$filelist"
        die "Unable to find $type metadata files."
    fi

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

        # Move away the converted files
        #rm -f -- "$jsonfile"
        info "Converted $type metadata '$jsonfile' to '$mylfile'."
        converted=$((converted + 1))
    done < "$filelist"

    rm -f -- "$filelist"

    notice "Change $type metadata upgrade complete: $converted converted, $skipped skipped, $failed failed."
    (( failed == 0 ))
}

definition_file_scope() {
    local maia_home="$1"
    local file="$2"
    local relative="${file#"$maia_home"/}"

    # Profiles can be nested below a session or workspace, so test them
    # before the session and workspace directory names.
    case "$relative" in
        profiles/*|*/profiles/*)
            printf '%s\n' profile
            ;;
        sessions/*)
            printf '%s\n' session
            ;;
        workspaces/*)
            printf '%s\n' workspace
            ;;
        *)
            printf '%s\n' home
            ;;
    esac
}

refresh_scopes() (
    # Refresh through the normal commands, because they initialize all of the
    # search data needed by the generators for the selected session/context.
    # The temporary session gives scoped refreshes an explicit workspace and
    # profile without changing the user's active session.
    local maia_home="$(resolve_home_dir)"
    local temporary_session="maia-temporary-update-refresh"
    local file relative scope session workspace profile profile_relative

    [[ -d "$maia_home" ]] || {
        notice "MAIA home '$maia_home' does not exist; nothing to refresh."
        return 0
    }

    # This name is reserved for update refresh.  Creating an existing session
    # is harmless and keeps this operation idempotent.
    "$MAIA_BIN" session create "$temporary_session" >/dev/null 2>&1 || true
    # Make sure to clean up even if Ctrl-C is entered
    trap '"$MAIA_BIN" session delete "maia-temporary-update-refresh" >/dev/null 2>&1 || true' EXIT INT TERM

    while IFS= read -r -d '' file; do
        relative="${file#"$maia_home"/}"
        scope="$(definition_file_scope "$maia_home" "$file")"
        session=""
        workspace=""
        profile=""

        case "$scope" in
            session)
                session="${relative#sessions/}"
                session="${session%%/*}"
                # Do not process the temporary session itself.
                [[ "$session" == "$temporary_session" ]] && continue
                export MAIA_SESSION="$session"
                ;;
            workspace)
                workspace="${relative#workspaces/}"
                workspace="${workspace%%/*}"
                export MAIA_SESSION="$temporary_session"
                "$MAIA_BIN" session set \
                    --workspace "$workspace" --profile "" || continue
                ;;
            profile)
                # A profile path has the form
                #   profiles/name/...
                # or
                #   sessions/name/profiles/profile/...
                # or
                #   workspaces/name/profiles/profile/...
                profile_relative="${relative#*profiles/}"
                profile_relative="${profile_relative%/*}"
                profile="${profile_relative//\/profiles\//%}"

                export MAIA_SESSION="$temporary_session"
                "$MAIA_BIN" session set \
                    --workspace "" --profile "$profile" || continue
                ;;
            home)
                export MAIA_SESSION="$temporary_session"
                "$MAIA_BIN" session set --workspace "" --profile "" || continue
                ;;
	    *)
		die "Unexpected scope '$scope'"
		;;
        esac

        case "$(basename "$file")" in
            toolset.txt)
                "$MAIA_BIN" tool --scope "$scope" refresh
                ;;
            skillset.txt)
                "$MAIA_BIN" skill --scope "$scope" refresh
                ;;
        esac
    done < <(find "$maia_home" -type f \( \
        -name 'toolset.txt' -o \
        -name 'skillset.txt' \
    \) -print0)

    # Remove the trap
    trap - EXIT INT TERM
    "$MAIA_BIN" session delete "$temporary_session" >/dev/null 2>&1 || true
)

handle_update_command() {
    # help flags
    [[ "$1" =~ ^-h|--help$ ]] && update_usage
    [[ "$2" =~ ^-h|--help$ ]] && update_usage

    local scope="home"
    load_config "$scope" CONFIG

    local cmd="${1:-upgrade}"
    shift || true

    case "$cmd" in
	"")
	    handle_update_command upgrade
	    #handle_update_command refresh
	    ;;
        upgrade)
            convert_change_json_files
            convert_config_json_files
            convert_session_json_files
            convert_profile_json_files
            convert_workspace_json_files
            ;;
        refresh)
            refresh_scopes
            ;;
        check)
            :
            ;;
        *)
            die "Unknown update command '$cmd'."
            ;;
    esac
}
