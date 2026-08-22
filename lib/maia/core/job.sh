# Background job management
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

job_usage() {
    cat <<'EOF'
USAGE

  maia job <command> [options]

Manage background jobs.

COMMANDS

  start <toolname> <toolargsjson>
    Start a new job as a tool call to be run in background.

  list
    List all jobs.

  show <id>
    Show job metadata.

  status <id>
    Show the status of the job:
      - Missing
        Job <id> does not exist.

      - Running
        Still running.

      - Completed(0)
        Finished with exit code = 0.

      - Failed(exitcode)
        Finished with exit code != 0.

      - Vanished
        Pid no longer exist but the finishing information is absent.

  output <id>
    Show the output produced by the job so far, including stderr.

  cancel <id>
    Cancel a running job.

  delete [--force] <id>
    Delete a job and its data. Cannot delete running jobs unless --force is specified.
    Force will try to cancel the job first. If that fails a warning will be shown.

  exist <id>
    Returns 0 if the job exists
    Returns 1 if the job do not exist
    No output, to be used in scripts

EOF
    exit 0
}

handle_job_command() {
    [[ "$1" =~ ^-h|--help$ ]] && job_usage

    local cmd="$1"
    shift
    
    local session="$(resolve_session_name)"
    local workspace_path="$(resolve_workspace_path)"
    local session_path="$(resolve_session_path)"

    case "$cmd" in
	start)
	    local tool="$1"
	    local toolargs="$2"
	    shift 2
	    mkdir -p "${session_path}/jobs"
	    local id="$(date +%Y%m%d%H%M%S)-$$-$(pid_starttime "$$")"
	    local enabled_tools_json=$(prompt_for_scope "session" "toolset" "json")
	    tool_fork "${session_path}/jobs" \
		      "$id" \
		      "$tool" \
		      "$toolargs" \
		      "$enabled_tools_json"
	    ;;

	list|ls)
	    if [[ -d "${session_path}/jobs" ]] ; then
		ls "${session_path}/jobs/"*.json | while read f ; do
		    local ff=$(basename "$f")
		    echo $ff
		done | sed 's/.json//;'
	    fi
            ;;

	show)
	    id="$1"
	    shift
	    if [[ ! -e "${session_path}/jobs/${id}.json" ]] ; then
		notice "Job with id '$id' does not exist."
	    fi
	    status="$(handle_job_command status "$id")"
	    jq \
		--arg status "$status" \
		'. + {status: $status}' \
		"${session_path}/jobs/${id}.json"
	    ;;

	status)
	    id="$1"
	    shift
	    if [[ ! -e "${session_path}/jobs/${id}.json" ]] ; then
		echo "Missing"
	    elif [[ -e "${session_path}/jobs/${id}.finished" ]] ; then
		local status=$(cat "${session_path}/jobs/${id}.finished")
		if [[ -z "$status" ]] ; then
		    echo "Vanished"
		elif [[ $status == 0 ]] ; then
		    echo "Completed(0)"
		else
		    echo "Failed($status)"
		fi
	    else
		local jpid=$(jq -r '.pid' "$meta")
		if ! kill -0 "$jpid" 2>/dev/null; then
		    : > "${session_path}/jobs/${id}.finished"
		    echo "Vanished"
		else
		    local pidstarttime="$(pid_starttime "$jpid")"
		    local jpidstarttime=$(jq -r '.pid' "$meta")
		    if [[ "$pidstarttime" == "$jpidstarttime" ]] ; then
			: > "${session_path}/jobs/${id}.finished"
			notice "Vanished"
		    else
		    	echo "Running"
		    fi
		fi
	    fi
	    ;;

	output)
	    id="$1"
	    shift
	    if [[ ! -e "${session_path}/jobs/${id}.output" ]] ; then
		echo "Missing output file"
	    else
		cat "${session_path}/jobs/${id}.output"
	    fi
	    ;;

	cancel)
	    id="$1"
	    shift

	    local meta="${session_path}/jobs/${id}.json"

	    if [[ ! -f "$meta" ]]; then
		notice "Job with id '$id' does not exist."
		return 1
	    fi

	    if [[ -f "${session_path}/jobs/${id}.finished" ]]; then
		notice "Job '$id' has already finished."
		return 1
	    fi

	    local jpid=$(jq -r '.pid' "$meta")

	    if ! kill -0 "$jpid" 2>/dev/null; then
		notice "Job '$id' is no longer running."
		: > "${session_path}/jobs/${id}.finished"
		return 1
	    fi
	    local pidstarttime="$(pid_starttime "$jpid")"
	    local jpidstarttime=$(jq -r '.pid' "$meta")
	    if [[ "$pidstarttime" == "$jpidstarttime" ]] ; then
		notice "Job '$id' is no longer running. Pid '$jpid' has been reused."
		: > "${session_path}/jobs/${id}.finished"
		return 1
	    fi

	    kill "$jpid"
	    #kill -- "-$jpid"
	    # Check output?
	    ;;

	delete)
	    id="$1"
	    shift
	    local force=false remove=false
	    if [[ "$1" == "--force" ]] ; then
		force=true
	    fi
	    if [[ -e "${session_path}/jobs/${id}.finished" ]] ; then
		remove=true
	    fi
	    handle_job_command cancel "$id"
	    if [[ -e "${session_path}/jobs/${id}.finished" ]] ; then
		remove=true
	    fi
	    if [[ "$remove" == true ]] ; then
		rm -f "${session_path}/jobs/${id}."*
	    fi
	    ;;

	exist)
            [[ -f "${session_path}/jobs/${id}.json" ]] || exit 1
	    exit 0
	    ;;

        *)
            session_usage
            ;;
    esac
}
