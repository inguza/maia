#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

. "$MAIA_TOOLS_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/session-common.sh"

declare -A param
parseparam

if [[ "$TOOL_NAME" == "session-file-explore" ]]; then
    set_subsession "${param[session]:-}"
fi
workspace_root="$(resolve_workspace_root)"
[[ -n "$workspace_root" && -d "$workspace_root" ]] || die "A workspace is required to explore pathspecs."
cd "$workspace_root" || die "Unable to enter workspace '$workspace_root'."

args=()
for option in max_new max_depth max_budget; do
    if [[ -v param[$option] ]]; then
        [[ "${param[$option]}" =~ ^[0-9]+$ ]] || die "$option must be a non-negative integer."
        cli_option="--${option//_/-}"
        args+=("$cli_option" "${param[$option]}")
    fi
done

if [[ ! -v param[pathspecs] ]]; then
    die "Missing parameter pathspecs."
fi

pathspecs=()
mapfile_from_json pathspecs "${param[pathspecs]}" || die "pathspecs parse error."
((${#pathspecs[@]} > 0)) || die "pathspecs must contain at least one pathspec."

paths=()
for pathspec in "${pathspecs[@]}"; do
    [[ -n "$pathspec" ]] || die "Pathspecs must not be empty."

    # A leading slash denotes a path from the workspace root, not a host path.
    while [[ "$pathspec" == /* ]]; do pathspec="${pathspec#/}"; done
    [[ -n "$pathspec" ]] || pathspec="."
    [[ "$pathspec" == "." ]] || validate_path "$pathspec"

    matches=()
    mapfile_from_command matches compgen -G "./$pathspec" || true
    ((${#matches[@]} > 0)) || die "Pathspec '$pathspec' did not match any workspace paths."
    paths+=("${matches[@]}")
done

args+=("${paths[@]}")

if [[ "$TOOL_NAME" == "session-file-explore" ]]; then
    "$MAIA_BIN" file explore "${args[@]}" 2>&1 | session_filter
else
    "$MAIA_BIN" file explore "${args[@]}" 2>&1
fi
