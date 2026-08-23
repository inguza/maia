#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

list_shells() {
    :
}

# Handle the maia tool command line
handle_shell_command() {
    # help
    [[ "$1" =~ ^-h|--help$ ]] && shell_usage
    [[ "$2" =~ ^-h|--help$ ]] && shell_usage

    local subcmd="${1:-}"
    shift
    
    case "$subcmd" in
	# Leave this for enter later
	# export PS1='\[\e]0;\u@\h[$MAIA_SESSION|$MAIA_SHELL]: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]\[\033[01;36m\][\[\033[00m\]$MAIA_SESSION\[\033[01;36m\]|\[\033[00m\]$MAIA_SHELL\[\033[01;36m\]]\[\033[00m\]:\[\033[01;35m\]\w\[\033[00m\]\$ '
	interactive|"")
	    (
		export PS1='\[\e]0;\u@\h[$MAIA_SESSION]: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]\[\033[01;36m\][\[\033[00m\]$MAIA_SESSION\[\033[01;36m\]]\[\033[00m\]:\[\033[01;35m\]\w\[\033[00m\]\$ '
		export PATH="$MAIA_ROOT/bin:$PATH"
		# TODO export functions
		notice "Entered MAIA shell"
		bash --noprofile --norc -i
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

tool_usage() {
    cat <<EOF
USAGE

  maia shell [command]
     Manage shells

COMMANDS

  interactive (default)
     Start an interactive shell with some extra help functionality in place.

EOF
    exit 0
}
