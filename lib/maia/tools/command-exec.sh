#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/file-common.sh"
. "$MAIA_TOOLS_LIB_DIR/exec-common.sh"

declare -A param
parseparam

declare -a command=()
if [[ -v 'param[command]' ]]; then
    if ! mapfile_from_json command "${param[command]}"; then
        die "Invalid command parameter encoding: expected a JSON array of strings."
    fi
fi
if ((${#command[@]} == 0)); then
    die "The command array must not be empty."
fi

command_name="${command[0]}"
if [[ -z "$command_name" ]]; then
    die "Command name must not be empty."
fi
command_args=("${command[@]:1}")

session_name="$(resolve_session_name)"
ws_path="$(resolve_workspace_path)"
if [[ -z "$ws_path" ]]; then
    die "No workspace defined."
fi
if ! cd "$ws_path"; then
    die "Cannot change to workspace root."
fi

if exec_approval_is_allowed "$command_name" "${command_args[@]}"; then
    # Execute the exact argv returned by the approval matcher. No shell is
    # involved, and this approved path creates no proposal or change-log entry.
    "$command_name" "${EXEC_APPROVED_ARGS[@]}"
else
    approval_status=$?
    if ((approval_status != 1)); then
        die "Unsafe path operand in approved command '$command_name'."
    fi
fi

# Approval failed: save a shell-quoted, single-command proposal for review.
requested_command=""
printf -v quoted '%q' "$command_name"
requested_command="$quoted"
for argument in "${command_args[@]}"; do
    printf -v quoted '%q' "$argument"
    requested_command+=" $quoted"
done

ws_changes="${ws_path}/changes/${session_name}"
baseid="${ASSISTANT_BASEID}"
index="$(find_index "$ws_changes" "$baseid")"
id="${baseid}-${index}"
wpath="$(shell_file_name "$ws_changes" "$id")"
mkdir -p "$(dirname "$wpath")"
printf '%s\n' "$requested_command" > "$wpath"
write_meta "$ws_changes" "$baseid" "$index" "" "shell exec"
printf '%b' "[NOTICE] Command execution was not approved.\nChange ID: $id\n\nThe requested command is now represented by this pending change id.\n"
exit 0
