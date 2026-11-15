#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

home_usage() {
    cat <<'EOF'
USAGE

  maia home <command> [<dir>]
  maia home

Manage your MAIA "home" (i.e. the directory where MAIA stores its metadata).

COMMANDS

  create [<dir>]
    Initialize an MAIA home in the given directory.
    If <dir> is omitted, defaults to the current working directory.

  delete [<dir>]
    Delete the MAIA home from the given directory.
    If <dir> is omitted, defaults to the current working directory.

  usage [--json] [today|<start> [<end>]]
    Show combined token usage across all sessions in this MAIA home.
    With no range, show home and today's totals. --json outputs machine-readable JSON.

  (no command)
    Show the current MAIA home directory.

OPTIONS

  -h, --help
    Show this help message.

EXAMPLES

  maia home create
    Initialize MAIA home in the current directory.

  maia home delete /path/to/home
    Delete the MAIA home at the specified directory.

  maia home usage
    Show combined token usage across all sessions in this MAIA home.

  maia home
    Show the current MAIA home directory.

NOTES

  The MAIA home directory stores metadata and configuration for the tool.
EOF
    exit 0
}

home_usage_command() {
    local sessions_dir="$1"
    shift

    local json=false
    local -a range_args=()
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--json" ]]; then
            json=true
        else
            range_args+=("$arg")
        fi
    done

    local mode="summary" start="" end="" label=""
    local today_key="$(date +%Y%m%d)"
    local today_label="$(date +%Y-%m-%d)"
    case ${#range_args[@]} in
        0)
            ;;
        1)
            if [[ "${range_args[0]}" == "last" ]]; then
                die "The 'last' usage selector is only available for a session."
            elif usage_is_date "${range_args[0]}"; then
                start="$(usage_normalize_time "${range_args[0]}" start)"
                end="$(usage_normalize_time "${range_args[0]}" end)"
                mode="range"
                case "${range_args[0]}" in
                    today) label="Usage today ($today_label)" ;;
                    yesterday)
                        local yesterday_label="$(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%d", localtime(time - 86400))')"
                        label="Usage yesterday ($yesterday_label)"
                        ;;
                    *) label="Usage on ${range_args[0]}" ;;
                esac
            else
                start="$(usage_normalize_time "${range_args[0]}" start)"
                end="$(date +%Y%m%dT%H%M%S)"
                [[ "$start" > "$end" ]] && die "Usage start time is in the future."
                mode="range"
                label="Usage from ${range_args[0]} through now"
            fi
            ;;
        2)
            start="$(usage_normalize_time "${range_args[0]}" start)"
            end="$(usage_normalize_time "${range_args[1]}" end)"
            [[ "$start" > "$end" ]] && die "Usage range start must not be after its end."
            mode="range"
            label="Usage from ${range_args[0]} through ${range_args[1]}"
            ;;
        *)
            die "Usage: maia home usage [--json] [today|<start> [<end>]]"
            ;;
    esac

    local -a usage_files=()
    if [[ -d "$sessions_dir" ]]; then
        shopt -s nullglob
        usage_files=("$sessions_dir"/*/usage.json)
        shopt -u nullglob
    fi

    local usage_data
    if ((${#usage_files[@]})); then
        usage_data="$(jq -s 'add // []' "${usage_files[@]}")" || die "Unable to read usage data from sessions in '$sessions_dir'."
    else
        usage_data='[]'
    fi

    local -a jq_args=(--arg mode "$mode" --arg today "$today_key" --arg today_label "$today_label" --arg start "$start" --arg end "$end" --arg label "$label" --argjson json "$json" -L "$MAIA_CORE_LIB_DIR" -f "$MAIA_CORE_LIB_DIR/usage-home.jq")
    if [[ "$json" == true ]]; then
        jq -c "${jq_args[@]}" <<< "$usage_data" || die "Unable to calculate home usage."
    else
        jq -r "${jq_args[@]}" <<< "$usage_data" || die "Unable to calculate home usage."
    fi
}

handle_home_command() {
    [[ "$1" =~ ^-h|--help$ ]] && home_usage
    [[ "$2" =~ ^-h|--help$ ]] && home_usage

    local scope="home"
    load_settings "$scope"

    local cmd=${1:-}
    local path=${2:-.}

    case "$cmd" in
        create)
            if [ ! -d "$path" ]; then
                die "'$path' is not a directory."
            fi
            if [ -d "${path}/.maia" ]; then
                die "'$path' is already initialized."
            fi
            mkdir -- "${path}/.maia"
            ;;

        usage)
            shift
            . "$MAIA_CORE_LIB_DIR/usage-common.sh"
            home_usage_command "$(resolve_session_base)" "$@"
            ;;

        delete)
            if [ ! -d "${path}/.maia" ]; then
                die "'$path' is not an maia home."
            fi
            # Protection against ../ tricks and symlink escapes
            local target
            target=$(realpath -- "${path}/.maia")
            if [ "${target##*/}" != ".maia" ]; then
                die "Refusing to remove invalid path: '$target'."
            fi
            rm -rf -- "$target"
            ;;

        ""|show)
            resolve_home_dir
            ;;

        *)
            die "Unknown command '$cmd'"
            ;;
    esac
}
