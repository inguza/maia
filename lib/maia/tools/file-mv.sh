#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/file-common.sh"

declare -A param
parseparam

declare -A allowed

declare -a paths=()
parsepathspecs pathspecs

if ((${#paths[@]} == 0)); then
    echo "[WARNING] No paths specified."
    exit 4
fi
destination="${param[destination]:-}"
if [[ -z "$destination" ]] ; then
    echo "[WARNING] No destination specified."
    exit 5
fi
validate_path "$destination"

session_name="$(resolve_session_name)"
ws_path="$(resolve_workspace_path)"
if [[ -z "$ws_path" ]] ; then
    die "No workspace defined."
fi
ws_changes="${ws_path}/changes/${session_name}"

baseid="${ASSISTANT_BASEID}"
index="$(find_index "$ws_changes" "$baseid")"
id="${baseid}-${index}"

wpath="$(action_file_name "$ws_changes" "$id")"
destdir=$(dirname -- "$destination")
if [[ "$destdir" != "." ]]; then
    printf '%s' "mkdir -p --" > "$wpath"
    printf ' %q' "$destdir" >> "$wpath"
    printf '\n' >> "$wpath"
else
    : > "$wpath"
fi
# Now to the complicated part, to determine what remembered files are changed
mapfile_from_command file_context $MAIA_BIN file list --raw
workspace_root="$(resolve_workspace_root)"
move_into_destination=false
if [[ -d "$destination" || ${#paths[@]} -gt 1 ]]; then
    move_into_destination=true
fi
declare -a remember=()
declare -a forget=()
for source in "${paths[@]}"; do
    source="${source%/}"
    # Fileset entries are workspace-relative and are canonicalized when
    # remembered. Normalize the source the same way so ./ and absolute
    # pathspecs still match their entries.
    source_key="$source"
    if [[ -n "$workspace_root" ]]; then
        source_key="$(realpath --relative-to="$workspace_root" -- "$source" 2>/dev/null)" || source_key="$source"
    fi
    for remembered in "${file_context[@]}"; do
	rfile="${remembered%%[|:]*}"
	rsuffix="${remembered:${#rfile}}"
	if [[ -d "$source" ]] ; then
	    [[ "$rfile" == "$source_key/"* ]] || continue
	    forget+=("$remembered")
	    rfile="${rfile#"$source_key"}"
	else
	    [[ "$rfile" == "$source_key" ]] || continue
	    forget+=("$remembered")
	    rfile=""
	fi
	if [[ "$move_into_destination" == true ]]; then
            remember+=("${destination%/}/$(basename "$source")${rfile}$rsuffix")
	else
	    remember+=("$destination$rsuffix")
	fi
    done
done

# Only forget entries that were actually present in the active filesets.
if ((${#forget[@]})); then
    printf '%s' "maia file forget" >> "$wpath"
    printf ' %q' "${forget[@]}" >> "$wpath"
    printf '\n' >> "$wpath"
fi

printf '%s' "mv -f --" >> "$wpath"
printf ' %q' "${paths[@]}" "$destination" >> "$wpath"
printf '\n' >> "$wpath"

# Do not generate an invalid empty remember command when none of the sources
# had entries in the active filesets.
if ((${#remember[@]})); then
    printf '%s' "maia file remember" >> "$wpath"
    printf ' %q' "${remember[@]}" >> "$wpath"
    printf '\n' >> "$wpath"
fi
# * join to one entry
write_meta "$ws_changes" "$baseid" "$index" "${paths[*]}"

declare -a targets=()
for source in "${paths[@]}"; do
    if [[ "$move_into_destination" == true ]]; then
        target="${destination%/}/$(basename -- "${source%/}")"
    else
        target="$destination"
    fi
    targets+=("$target")
done
if approval_is_allowed delete "${paths[@]}" && approval_is_allowed create "${targets[@]}"; then
    "$MAIA_BIN" change run "$id" >/dev/null 2>&1 || true
    status_file="$ws_changes/${id}-finished.exit_status"
    if [[ -f "$status_file" && "$(read_file "$status_file")" == "0" ]]; then
        printf '[NOTICE] The requested change has been applied. The change has been logged.\nChange ID: %s\n' "$id"
        exit 0
    fi
    printf '[ERROR] The requested change failed.\nChange ID: %s\n' "$id" >&2
    exit 1
fi

printf '%b' "[NOTICE] The requested file change requires approval. A pending change is ready for review.\nChange ID: $id\nReview the change and decided whether to 'do' it or skip it."
exit 0
