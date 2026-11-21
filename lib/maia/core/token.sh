#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

GUI_DEFAULT_PORT=${GUI_DEFAULT_PORT:-8000}
GUI_DEFAULT_BIND=${GUI_DEFAULT_BIND:-127.0.0.1}

# Authentication tokens are stored separately from gui.myl because they are
# bearer credentials and should have more restrictive file permissions.
gui_auth_file() {
    echo "$(resolve_home_dir)/auth.myl"
}

gui_auth_hash() {
    local salt="$1" secret="$2"
    printf '%s' "${salt}:${secret}" | sha256sum | awk '{print $1}'
}

gui_auth_token_lines() {
    local file="$(gui_auth_file)"
    [[ -f "$file" ]] || return 0
    myl_get "$file" tokens
}

gui_auth_has_tokens() {
    [[ -n "$(gui_auth_token_lines)" ]]
}

gui_auth_validate_name() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]
}

gui_auth_create_token() {
    local name="${1:-auto}"
    gui_auth_validate_name "$name" || die "Invalid token name '$name'. Use only letters, digits, '_' and '-'."
    local file="$(gui_auth_file)"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    chmod 600 "$file"
    local salt secret hash record
    salt="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
    secret="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
    hash="$(gui_auth_hash "$salt" "$secret")"
    record="${name}:${salt}:${hash}"
    myl_append "$file" tokens "$record"
    GUI_AUTH_IDENTIFIER="${name}:${salt}"
    GUI_AUTH_SECRET="$secret"
}

gui_auth_list() {
    local line name salt hash
    while IFS= read -r line; do
        [[ "$line" =~ ^([^:]+):([0-9a-f]+):([0-9a-f]{64})$ ]] || continue
        name="${BASH_REMATCH[1]}"
        salt="${BASH_REMATCH[2]}"
        printf '%s:%s\n' "$name" "$salt"
    done < <(gui_auth_token_lines)
}

gui_auth_delete() {
    local identifier="$1" file="$(gui_auth_file)" line name salt hash
    [[ "$identifier" =~ ^([A-Za-z0-9_-]+):([0-9a-f]+)$ ]] || die "Invalid token identifier '$identifier'."
    local found=0
    local -a remaining=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=: read -r name salt hash <<< "$line"
        if [[ "${name}:${salt}" == "$identifier" ]]; then
            found=1
        else
            remaining+=("$line")
        fi
    done < <(gui_auth_token_lines)
    (( found )) || die "Authentication token '$identifier' does not exist."
    myl_update "$file" tokens "${remaining[@]}"
    notice "Deleted authentication token '$identifier'."
}

gui_auth_clear() {
    local file="$(gui_auth_file)"
    if [[ -f "$file" ]]; then
        myl_delete "$file" tokens
        notice "Cleared all authentication tokens."
    else
        notice "No authentication tokens exist."
    fi
}

# Return a host suitable for displaying in a browser URL.
gui_url_host() {
    local bind="$1"

    case "$bind" in
        0.0.0.0|::)
            local host="$(hostname -I 2>/dev/null | awk '{print $1}')"
            printf '%s' "${host:-localhost}"
            ;;
        *)
            printf '%s' "$bind"
            ;;
    esac
}

gui_auth_fragment() {
    printf '%s:%s' "${GUI_AUTH_IDENTIFIER#*:}" "$GUI_AUTH_SECRET"
}

gui_auth_qr_url() {
    local bind="$1"
    local port="$2"
    local fragment="$3"
    printf 'http://%s:%s/qr#auth=%s' "$(gui_url_host "$bind")" "$port" "$fragment"
}

gui_auth_create_and_print_url() {
    local name="${1:-auto}"
    local public_url="${2:-}"
    local gui_dir="$(resolve_home_dir)"
    local gui_meta="$gui_dir/gui.myl"
    local bind="$(myl_get "$gui_meta" bind 2>/dev/null || true)"
    local port="$(myl_get "$gui_meta" port 2>/dev/null || true)"
    bind="${bind:-${MAIA_GUI_BIND:-$GUI_DEFAULT_BIND}}"
    port="${port:-$GUI_DEFAULT_PORT}"
    if [[ -n "$public_url" && ! "$public_url" =~ ^https?://[^[:space:]]+$ ]]; then
        die "Invalid public URL '$public_url'. Expected http:// or https:// URL."
    fi
    public_url="${public_url%/}"
    gui_auth_create_token "$name"
    local fragment="$(gui_auth_fragment)"
    if [[ -n "$public_url" ]]; then
        GUI_AUTH_URL="$public_url/#auth=$fragment"
        GUI_AUTH_QR_URL="$public_url/qr#auth=$fragment"
    else
        GUI_AUTH_URL="http://$(gui_url_host "$bind"):$port/#auth=$fragment"
        GUI_AUTH_QR_URL="$(gui_auth_qr_url "$bind" "$port" "$fragment")"
    fi
    printf 'MAIA GUI: %s\n' "$GUI_AUTH_URL"
    printf 'MAIA QR:  %s\n' "$GUI_AUTH_QR_URL"
}

token_usage() {
    cat <<EOF
USAGE

  maia token [command]
     Create and manage MAIA GUI authentication tokens.

COMMANDS

  create [<name>] [--url <url>]
     Create a token and print an authenticated GUI URL.
     --url specifies the public MAIA URL, including an optional subpath.

  list
     List authentication token identifiers.

  delete <name>:<salt>
     Delete one authentication token.

  clear
     Delete all authentication tokens.

OPTIONS

  -h, --help
     Show this help message and exit.

EOF
    exit 0
}

handle_token_command() {
    [[ "$1" =~ ^-h|--help$ ]] && token_usage
    [[ "$2" =~ ^-h|--help$ ]] && token_usage
    local subcommand="${1:-}"
    [[ $# -gt 0 ]] && shift

    case "$subcommand" in
        create)
            local name=auto
            local name_set=false
            local public_url=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --url)
                        [[ -n "${2:-}" ]] || die "Option --url requires a URL."
                        public_url="$2"
                        shift 2
                        ;;
                    --*)
                        die "Unknown token create option '$1'."
                        ;;
                    *)
                        [[ "$name_set" == false ]] || die "The token create command accepts at most one name."
                        name="$1"
                        name_set=true
                        shift
                        ;;
                esac
            done
            gui_auth_create_and_print_url "$name" "$public_url"
            ;;
        list)
            [[ $# -eq 0 ]] || die "The token list command does not accept arguments."
            gui_auth_list
            ;;
        delete)
            [[ $# -eq 1 ]] || die "The token delete command requires a token identifier."
            gui_auth_delete "$1"
            ;;
        clear)
            [[ $# -eq 0 ]] || die "The token clear command does not accept arguments."
            gui_auth_clear
            ;;
        -h|--help|"")
            token_usage
            ;;
        *)
            die "Unknown token command '$subcommand'. Run 'maia token --help' for instructions."
            ;;
    esac
}
