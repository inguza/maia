#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

# Handle the maia tool command line
handle_shell_command() {
    # help
    [[ "$1" =~ ^-h|--help$ ]] && shell_usage
    [[ "$2" =~ ^-h|--help$ ]] && shell_usage

    local subcmd="${1:-}"
    shift
    
    case "$subcmd" in
	list)
	    local base="$(resolve_shell_base)"
	    printf "  %-30s %-10s\n" "NAME" "STATE"
	    for dir in $(ls $base >2/dev/null) ; do
		if [[ -d "$base/$dir" ]] ; then
		    local status=unknown
		    if [[ -e "$base/$dir/exit_status" ]] ; then
			local exit_status=$(cat "$base/$dir/exit_status")
			if [[ -z "$exit_status" ]] ; then
			    status="created"
			elif [[ "$exit_status" == 0 ]] ; then
			    status="finished"
			else
			    status="failed"
			fi
		    else
			status="running"
		    fi
		    local x=""
		    if [[ "$MAIA_SHELL" == "$dir" ]] ; then
			x="*"
		    fi
		    printf "%-1s %-30s %-10s\n" "$x" "$dir" "$status"
		fi
	    done
	;;
	
	create)
	    local xn="$1"
	    if [[ -n "$1" ]] ; then
		shift
	    fi
	    local name="$(resolve_shell_name "$xn")"
	    local path="$(resolve_shell_path "$name")"

	    if [[ -d "$path" ]] ; then
		warn "Shell '$name' already exists."
	    else
		notice "Created monitored shell '$name'."
		mkdir -p "$path"
		touch "$path/exit_status"
	    fi
	    ;;

	delete|remove)
	    local xn="$1"
	    if [[ -n "$1" ]] ; then
		shift
	    fi
	    local name="$(resolve_shell_name "$xn")"
	    if [[ "$MAIA_SHELL" == "$name" ]] ; then
		die "Cannot remove shell '$name' while inside it."
	    fi
	    local path="$(resolve_shell_path "$name")"
	    if [[ ! -d "$path" ]] ; then
		die "Shell '$name' does not exist."
	    elif [[ ! -e "$path/exit_status" ]] ; then
		die "Cannot remove shell '$name' while running."
	    else
		notice "Removing monitored shell '$name'."
		rm -Rf "$path"
	    fi
	    ;;

	clear)
	    local xn="$1"
	    if [[ -n "$1" ]] ; then
	        shift
            fi
            local name="$(resolve_shell_name "$xn")"
            local path="$(resolve_shell_path "$name")"
            if [[ ! -d "$path" ]] ; then
                die "Shell '$name' does not exist."
	    fi
            notice "Cearling monitored shell '$name'."
	    echo "Shell cleared at `date`" > "$path/output"
	    ;;

	enter)
	    local xn="$1"
	    if [[ -n "$1" ]] ; then
		shift
	    fi
	    local name="$(resolve_shell_name "$xn")"
	    local path="$(resolve_shell_path "$name")"
	    if [[ "$name" == "default" && ! -d "$path" ]] ; then
		handle_shell_command create default
	    fi
	    if [[ ! -d "$path" ]] ; then
		error "Shell '$name' does not exist."
		return
	    fi
	    if [[ ! -e "$path/exit_status" ]] ; then
	       warn "Double enter of monitored shell '$name'"
	    fi
	    (
		export MAIA_PS1='\[\e]0;\u@\h[$MAIA_SESSION|$MAIA_SHELL]: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]\[\033[01;36m\][\[\033[00m\]$MAIA_SESSION\[\033[01;36m\]|\[\033[00m\]$MAIA_SHELL\[\033[01;36m\]]\[\033[00m\]:\[\033[01;35m\]\w\[\033[00m\]\$ '
		export PATH="$MAIA_ROOT/bin:$PATH"
		export MAIA_SHELL="$name"
		# TODO export functions
		notice "Entered monitored MAIA shell '$name' ($path)"
		rm -f "$path/exit_status"
		script -q -f -a -c 'bash --noprofile --rcfile "'$MAIA_ROOT/etc/bashrc'" -i' "$path/output"
		exit_status=$?
		notice "Left monitored MAIA shell '$name'"
		echo "$exit_status" > "$path/exit_status"
	    )

	    ;;
	# Leave this for enter later
	interactive|"")
	    (
		export MAIA_PS1='\[\e]0;\u@\h[$MAIA_SESSION]: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]\[\033[01;36m\][\[\033[00m\]$MAIA_SESSION\[\033[01;36m\]]\[\033[00m\]:\[\033[01;35m\]\w\[\033[00m\]\$ '
		export PATH="$MAIA_ROOT/bin:$PATH"
		# TODO export functions
		notice "Entered MAIA shell"
		bash --noprofile --rcfile "$MAIA_ROOT/etc/bashrc" -i
		notice "Left MAIA shell"
	    )
	    ;;
	"")
	    
	    ;;
        *)
            die "Unknown tool command: $subcmd"
            ;;
    esac
}

shell_usage() {
    cat <<EOF
USAGE

  maia shell [command]
     Manage shells

COMMANDS

  list
    List monitored shells.

  create [<name>]
    Create a named monitored and interactive shell.

  delete [<name>]
    Delete a named monitored shell.

  remove
    Alias of delete.

  enter [<name>]
    Enter a named monitored shell.

  interactive (default)
     Start an interactive shell with some extra help functionality in place.

EOF
    exit 0
}
