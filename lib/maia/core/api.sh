#
# Handles AI introspection ("maia api") commands: models, model, fine-tunes, fine-tune, usage
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

api_usage() {
    cat <<'EOF'
USAGE

  maia api <command> [options]

Commands for interacting with OpenAI API resources.

COMMANDS

  models [--system] [--internal]
    List available model IDs. By default, only models owned by "openai" are shown.
    --system    Include models owned by "system" (preview or variant builds).
    --internal  Include models owned by "openai-internal" (internal-only models).
   For AWS it lists all without any filtering capability.

  model <model_id>
    Show full metadata for the specified model ID, including permissions
    and availability details.
    Now implemented for AWS.

  fine-tunes
    List all fine-tune jobs associated with your account, including status,
    training metrics, and resulting model IDs.
    Now implemented for AWS.

  fine-tune <job_id>
    Show detailed information for the specified fine-tune job, such as
    hyperparameters, dataset size, and completion status.
    Now implemented for AWS.

OPTIONS

  -h, --help
    Show this help message and exit.

EXAMPLES

    maia api models
      List available models.

    maia api model text-davinci-003
      Show details for the text-davinci-003 model.

NOTES

  Use the --system or --internal flags to filter models.
EOF
    exit 0
}

# Do not yet dislplay the usage function because it does not seem to work
#  usage [--start YYYY-MM-DD] [--end YYYY-MM-DD]
#    Display billing and usage statistics for your OpenAI account.
#    Defaults to the past 30 days if no dates are provided.
#    --start     Start date for usage (inclusive).
#    --end       End date for usage (inclusive).


handle_api_command() {
    # If no subcommand or help flag, display help
    [[ "$1" =~ ^-h|--help$ ]] && api_usage
    [[ "$2" =~ ^-h|--help$ ]] && api_usage
    local maia_api_base_url="$(echo "$_cfg" | jq -r '.api_base_url')"
    local api_type=$(jq -r '.api_type' <<<"$_cfg")
    # Detect API type
    if [[ "$api_type" == "AUTODETECT" || -z "$api_type" ]] ; then
	if [[ "${maia_api_base_url}" == *"bedrock"*"amazonaws.com"* ]] ; then
	    api_type="AWS_BEDROCK_CONVERSE"
	else
	    # Default
	    api_type="OPENAI_CHAT_COMPLETIONS"
	fi
    fi
    # Ensure API key is set
    if [[ "$api_type" == "OPENAI_CHAT_COMPLETIONS" && -z "$OPENAI_API_KEY" ]]; then
        die "OPENAI_API_KEY or OPENAI_API_KEY environment variable is not set."
    fi
    # Prepare extra headers from env var (from common.sh helper)
    local curl_headers=()
    local url=""
    local METHOD="GET"
    if [[ "$api_type" == "AWS_BEDROCK_CONVERSE" ]] ; then
	url="$(echo $maia_api_base_url | sed 's/-runtime//;')"
	curl_headers+=(-X "$METHOD")
	. "$MAIA_CORE_LIB_DIR/aws.sh"
    else
	curl_headers+=( -H "Authorization: Bearer $OPENAI_API_KEY" )
	url="$maia_api_base_url"
    fi
    curl_extra_headers curl_headers

    local cmd="$1"; shift
    case "$cmd" in
	models)
	    # List available models (only show IDs, filter by ownership)
	    local include_system=false include_internal=false
	    # Parse flags
	    while [[ "$1" =~ ^- ]]; do
		case "$1" in
		    --system) include_system=true; shift;;
		    --internal) include_internal=true; shift;;
		    *) echo "Unknown option: $1" >&2; return 1;;
		esac
	    done
	    # Build ownership condition
	    local condition='(.owned_by == "openai")'
	    if [[ "$include_system" == true ]]; then
		condition+=' or (.owned_by == "system")'
	    fi
	    if [[ "$include_internal" == true ]]; then
		condition+=' or (.owned_by == "openai-internal")'
	    fi
	    # Fetch and filter model IDs using select
	    if [[ "$api_type" == "OPENAI_CHAT_COMPLETIONS" ]] ; then
		curl -sS \
		     "${curl_headers[@]}" \
		     "$url/v1/models" \
		    | jq -r ".data[] | select($condition) | .id"
	    elif [[ "$api_type" == "AWS_BEDROCK_CONVERSE" ]] ; then
		readarray -t SIGNED_HEADERS < <(sigv4headers "$METHOD" "$url/foundation-models" "bedrock" "")
		for hdr in "${SIGNED_HEADERS[@]}"; do
		    curl_headers+=(-H "$hdr")
		done
		curl -sS \
		     "${curl_headers[@]}" \
		     "$url/foundation-models" \
		    | jq -r "."
	    else
		die "Unknown api type '$api_type'"
	    fi
	    ;;

	model)
	    # Show details for a single model
	    if [[ -z "$1" ]]; then
		api_usage
		exit 1
	    fi
	    local model_id="$1"
	    if [[ "$api_type" == "OPENAI_CHAT_COMPLETIONS" ]] ; then
		curl -sS -H "Authorization: Bearer $OPENAI_API_KEY" \
		     "${extra_headers[@]}" \
		     "$maia_api_base_url/v1/models/$model_id" | jq .
	    elif [[ "$api_type" == "AWS_BEDROCK_CONVERSE" ]] ; then
		die "Get model not implemented for AWS Bedrock."
	    else
		die "Unknown api type '$api_type'"
	    fi
	    ;;

	fine-tunes)
	    # List fine-tune jobs
	    if [[ "$api_type" == "OPENAI_CHAT_COMPLETIONS" ]] ; then
		curl -sS -H "Authorization: Bearer $OPENAI_API_KEY" \
		     "${extra_headers[@]}" \
		     "$maia_api_base_url/v1/fine-tunes" | jq .
	    elif [[ "$api_type" == "AWS_BEDROCK_CONVERSE" ]] ; then
		die "List fine-tunes not implemented for AWS Bedrock."
	    else
		die "Unknown api type '$api_type'"
	    fi
	    ;;

	fine-tune)
	    # Show details for a single fine-tune job
	    if [[ -z "$1" ]]; then
		api_usage
		exit 1
	    fi
	    if [[ "$api_type" == "OPENAI_CHAT_COMPLETIONS" ]] ; then
		local job_id="$1"
		curl -sS -H "Authorization: Bearer $OPENAI_API_KEY" \
		     "${extra_headers[@]}" \
		     "$maia_api_base_url/v1/fine-tunes/$job_id" | jq .
	    elif [[ "$api_type" == "AWS_BEDROCK_CONVERSE" ]] ; then
		die "Get fine-tune not implemented for AWS Bedrock."
	    else
		die "Unknown api type '$api_type'"
	    fi
	    ;;

	usage)
	    # Show usage. Defaults to past 30 days; supports optional date flags
	    # Usage: maia api usage [--start YYYY-MM-DD] [--end YYYY-MM-DD]
	    while [[ "$1" =~ ^- ]]; do
		case "$1" in
		    --start)
			start_date="$2"; shift 2;;
		    --end)
			end_date="$2"; shift 2;;
		    *)
			die "Unknown option: $1"
		esac
	    done
	    if [[ "$api_type" == "OPENAI_CHAT_COMPLETIONS" ]] ; then
		# Default to past 30 days
		local start_date="${start_date:-$(date -I -d '30 days ago')}"
		local end_date="${end_date:-$(date -I)}"
		curl -sS -G \
		     -H "Authorization: Bearer $OPENAI_API_KEY" \
		     "${extra_headers[@]}" \
		     --data-urlencode "start_date=$start_date" \
		     --data-urlencode "end_date=$end_date" \
		     "$maia_api_base_url/v1/dashboard/billing/usage" | jq .
	    elif [[ "$api_type" == "AWS_BEDROCK_CONVERSE" ]] ; then
		die "Usage not implemented for AWS Bedrock."
	    else
		die "Unknown api type '$api_type'"
	    fi
	    ;;

	*)
	    die "Unknown command $1"
	    ;;
    esac
}
