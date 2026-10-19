#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

GUI_DEFAULT_PORT=8000
GUI_MAX_PORT_ATTEMPTS=20
GUI_DEFAULT_BIND=127.0.0.1
GUI_AUTH_COOKIE_MAX_AGE=31536000

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

gui_usage() {
    cat <<EOF
USAGE

  maia gui [command]
     Start and manage the MAIA web GUI.

COMMANDS

  start [--bind <address>] [--launch]
     Start the MAIA web GUI using PHP's built-in web server.

     The default bind address is 127.0.0.1. Use --bind 0.0.0.0 to listen on
     all interfaces.

  stop
     Stop the running MAIA web GUI server.

  launch [<url>]
     Open the supplied URL, or http://localhost:<port>/ when no URL is supplied.

  create [<name>] [--launch]
     Create an authentication token and print an authenticated URL.

  list
     List authentication token identifiers.

  delete <name>:<salt>
     Delete one authentication token.

  clear
     Delete all authentication tokens.

OPTIONS

  -h, --help
     Show this help message and exit.

ENVIRONMENT

  MAIA_BROWSER
     Command used to open the GUI URL after the server starts.

  MAIA_GUI_BIND
     Default bind address, overridden by --bind.

EOF
    exit 0
}

gui_print_url() {
    local bind="$1"
    local port="$2"
    local fragment="${3:-}"
    local host
    host="$(gui_url_host "$bind")"
    if [[ -n "$fragment" ]]; then
        printf 'MAIA GUI: http://%s:%s/#auth=%s\n' "$host" "$port" "$fragment"
    else
        printf 'MAIA GUI: http://%s:%s/\n' "$host" "$port"
    fi
}

gui_auth_fragment() {
    printf '%s:%s' "${GUI_AUTH_IDENTIFIER#*:}" "$GUI_AUTH_SECRET"
}

gui_auth_create_and_print_url() {
    local name="${1:-auto}"
    local gui_dir="$(resolve_home_dir)"
    local gui_meta="$gui_dir/gui.myl"
    local bind="$(myl_get "$gui_meta" bind 2>/dev/null || true)"
    local port="$(myl_get "$gui_meta" port 2>/dev/null || true)"
    bind="${bind:-${MAIA_GUI_BIND:-$GUI_DEFAULT_BIND}}"
    port="${port:-$GUI_DEFAULT_PORT}"
    gui_auth_create_token "$name"
    GUI_AUTH_URL="http://$(gui_url_host "$bind"):$port/#auth=$(gui_auth_fragment)"
    printf 'MAIA GUI: %s\n' "$GUI_AUTH_URL"
}

gui_server_is_running() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

gui_server_ready() {
    local bind="$1"
    local port="$2"
    local host="$bind"

    # 0.0.0.0 is a listen address, not a destination address.
    [[ "$host" == "0.0.0.0" ]] && host="127.0.0.1"
    [[ "$host" == "::" ]] && host="[::1]"

    curl -sS --max-time 1 "http://$host:$port/status" >/dev/null 2>&1
}

gui_start_server() {
    local bind="$1"
    local port="$2"
    local gui_dir="$3"
    local webroot="$MAIA_ROOT/lib/maia/web"
    local logfile="$gui_dir/server.log"
    local pid
    local attempt

    [[ -d "$webroot" ]] || die "MAIA webroot does not exist: $webroot"

    php -S "$bind:$port" -t "$webroot" "$webroot/router.php" >"$logfile" 2>&1 </dev/null &
    pid=$!

    # Give PHP a short time to bind and answer requests. A failed bind normally
    # terminates the process immediately.
    for (( attempt=0; attempt<20; attempt++ )); do
        if ! gui_server_is_running "$pid"; then
            return 1
        fi
        if gui_server_ready "$bind" "$port"; then
            printf '%s' "$pid"
            return 0
        fi
        sleep 0.1
    done

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
}

gui_launch_browser() {
    local url="$1"
    local -a browser_command=()

    if [[ -n "${MAIA_BROWSER:-}" ]]; then
        read -r -a browser_command <<< "$MAIA_BROWSER"
    elif [[ "${MSYSTEM:-}" =~ ^(MINGW|MSYS|CYGWIN) ]]; then
        if command -v cmd.exe >/dev/null 2>&1; then
            browser_command=(cmd.exe /c start "" "$url")
        fi
    elif [[ "$(uname -a 2>/dev/null)" == *Microsoft* || "$(uname -a 2>/dev/null)" == *microsoft* ]]; then
        if command -v wslview >/dev/null 2>&1; then
            browser_command=(wslview "$url")
        elif command -v powershell.exe >/dev/null 2>&1; then
            browser_command=(powershell.exe -NoProfile -Command Start-Process "$url")
        fi
    elif [[ "$(uname -s 2>/dev/null)" == Darwin* ]]; then
        command -v open >/dev/null 2>&1 && browser_command=(open "$url")
    else
        if command -v xdg-open >/dev/null 2>&1; then
            browser_command=(xdg-open "$url")
        elif command -v gio >/dev/null 2>&1; then
            browser_command=(gio open "$url")
        elif command -v sensible-browser >/dev/null 2>&1; then
            browser_command=(sensible-browser "$url")
        fi
    fi

    if [[ ${#browser_command[@]} -eq 0 ]]; then
        warn "Unable to find a browser launcher. Set MAIA_BROWSER or open the URL manually."
        return 1
    fi
    "${browser_command[@]}" >/dev/null 2>&1 &
}

gui_stop() {
    local gui_dir
    local gui_meta
    local stored_pid
    local command
    local attempt

    gui_dir="$(resolve_home_dir)"
    gui_meta="$gui_dir/gui.myl"
    stored_pid="$(myl_get "$gui_meta" pid 2>/dev/null || true)"

    if [[ ! "$stored_pid" =~ ^[0-9]+$ ]]; then
        myl_delete "$gui_meta" pid 2>/dev/null || true
        printf 'MAIA GUI is not running.\n'
        return 0
    fi

    if ! gui_server_is_running "$stored_pid"; then
        myl_delete "$gui_meta" pid 2>/dev/null || true
        printf 'MAIA GUI is not running.\n'
        return 0
    fi

    command="$(ps -p "$stored_pid" -o args= 2>/dev/null || true)"
    if [[ "$command" != *"php -S"* || "$command" != *"$MAIA_ROOT/lib/maia/web"* ]]; then
        warn "PID $stored_pid is not recognized as the MAIA GUI server; it was not stopped."
        myl_delete "$gui_meta" pid 2>/dev/null || true
        return 1
    fi

    kill "$stored_pid" 2>/dev/null || true
    for (( attempt=0; attempt<20; attempt++ )); do
        if ! gui_server_is_running "$stored_pid"; then
            myl_delete "$gui_meta" pid 2>/dev/null || true
            printf 'MAIA GUI stopped.\n'
            return 0
        fi
        sleep 0.1
    done

    warn "MAIA GUI did not stop after receiving SIGTERM; sending SIGKILL."
    kill -KILL "$stored_pid" 2>/dev/null || true
    myl_delete "$gui_meta" pid 2>/dev/null || true
    printf 'MAIA GUI stopped.\n'
}

gui_launch() {
    local url="${1:-}"
    if [[ -z "$url" ]]; then
        local gui_dir="$(resolve_home_dir)"
        local gui_meta="$gui_dir/gui.myl"
        local port="$(myl_get "$gui_meta" port 2>/dev/null || true)"
        port="${port:-$GUI_DEFAULT_PORT}"
        [[ "$port" =~ ^[0-9]+$ ]] || die "Invalid MAIA GUI port '$port'."
        url="http://localhost:$port/"
    fi

    printf 'Launching MAIA GUI at %s\n' "$url"
    gui_launch_browser "$url"
}

gui_start() {
    local gui_dir
    local gui_meta
    local stored_port
    local stored_pid
    local stored_bind
    local bind=""
    local port
    local pid
    local url
    local launch=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bind)
                [[ -n "${2:-}" ]] || die "Option --bind requires an address."
                bind="$2"
                shift 2
                ;;
            --launch)
                launch=true
                shift
                ;;
            -h|--help)
                gui_usage
                ;;
            *)
                die "Unknown gui start option '$1'."
                ;;
        esac
    done

    require_command php

    gui_dir="$(resolve_home_dir)"
    export MAIA_HOME="$gui_dir"
    mkdir -p "$gui_dir"
    gui_meta="$gui_dir/gui.myl"

    stored_port="$(myl_get "$gui_meta" port 2>/dev/null || true)"
    stored_pid="$(myl_get "$gui_meta" pid 2>/dev/null || true)"
    stored_bind="$(myl_get "$gui_meta" bind 2>/dev/null || true)"

    [[ -n "$bind" ]] || bind="${stored_bind:-${MAIA_GUI_BIND:-$GUI_DEFAULT_BIND}}"

    # Reuse a running server described by gui.myl.
    if [[ "$bind" == "$stored_bind" ]] && gui_server_is_running "$stored_pid" &&
       gui_server_ready "$bind" "$stored_port"; then
        local auth_fragment=""
        if ! gui_auth_has_tokens; then
            gui_auth_create_token auto
            auth_fragment="$(gui_auth_fragment)"
        fi
        url="http://$(gui_url_host "$bind"):$stored_port/"
        [[ -n "$auth_fragment" ]] && url+="#auth=$auth_fragment"
        printf 'MAIA GUI is already running at %s\n' "$url"
        if [[ "$launch" == true ]]; then
            gui_launch_browser "$url"
        fi
        return 0
    fi

    if [[ "$stored_port" =~ ^[0-9]+$ ]]; then
        port="$stored_port"
    else
        port="$GUI_DEFAULT_PORT"
    fi

    for (( attempt=0; attempt<GUI_MAX_PORT_ATTEMPTS; attempt++ )); do
        if pid="$(gui_start_server "$bind" "$port" "$gui_dir")"; then
            myl_update "$gui_meta" port "$port"
            myl_update "$gui_meta" pid "$pid"
            myl_update "$gui_meta" bind "$bind"

            local auth_fragment=""
            if ! gui_auth_has_tokens; then
                gui_auth_create_token auto
                auth_fragment="$(gui_auth_fragment)"
            fi
            url="http://$(gui_url_host "$bind"):$port/"
            [[ -n "$auth_fragment" ]] && url+="#auth=$auth_fragment"
            printf 'MAIA GUI started at %s\n' "$url"
            if [[ "$launch" == true ]]; then
                gui_launch_browser "$url"
            fi
            return 0
        fi
        port=$((port + 1))
    done

    die "Unable to start the MAIA GUI on ports $((port-GUI_MAX_PORT_ATTEMPTS))-$((port-1))."
}

handle_gui_command() {
    local subcommand="${1:-start}"
    [[ $# -gt 0 ]] && shift

    case "$subcommand" in
        start)
            gui_start "$@"
            ;;
        stop)
            [[ $# -eq 0 ]] || die "The gui stop command does not accept arguments."
            gui_stop
            ;;
        launch)
            [[ $# -le 1 ]] || die "The gui launch command accepts at most one URL."
            gui_launch "${1:-}"
            ;;
        create)
            local launch=false
            local name=auto
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --launch)
                        launch=true
                        shift
                        ;;
                    -h|--help)
                        gui_usage
                        ;;
                    *)
                        [[ "$name" == auto ]] || die "The gui create command accepts at most one name."
                        name="$1"
                        shift
                        ;;
                esac
            done
            gui_auth_create_and_print_url "$name"
            if [[ "$launch" == true ]]; then
                gui_launch_browser "$GUI_AUTH_URL"
            fi
            ;;
        list)
            [[ $# -eq 0 ]] || die "The gui list command does not accept arguments."
            gui_auth_list
            ;;
        delete)
            [[ $# -eq 1 ]] || die "The gui delete command requires a token identifier."
            gui_auth_delete "$1"
            ;;
        clear)
            [[ $# -eq 0 ]] || die "The gui clear command does not accept arguments."
            gui_auth_clear
            ;;
        -h|--help)
            gui_usage
            ;;
        *)
            die "Unknown gui command '$subcommand'. Run 'maia gui --help' for instructions."
            ;;
    esac
}
