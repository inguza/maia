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

  maia home
    Show the current MAIA home directory.

NOTES

  The MAIA home directory stores metadata and configuration for the tool.
EOF
    exit 0
}

handle_home_command() {
    [[ "$1" =~ ^-h|--help$ ]] && home_usage
    [[ "$2" =~ ^-h|--help$ ]] && home_usage
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
