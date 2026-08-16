#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
###################### AWS support ######################
HMAC() {
    printf '%s' "$2" | openssl dgst -binary -sha256 -mac HMAC -macopt "hexkey:$1" | xxd -p -c 256
}

sigv4headers() {
    local METHOD="$1"
    local url="$2"
    local SERVICE="$3"
    local PAYLOAD="$4"
    local HOST=$(echo "$url" | sed -n 's|https://\([^/]*\)/.*|\1|p')
    local REGION=$(echo "$HOST" | sed -n 's|^[^.]*\.\([^.]*\)\.amazonaws\.com$|\1|p')
    #debug "REGION=$REGION ($url)"
    local URI=$(echo "$url" | sed -n 's|https://[^/]*/\(.*\)|/\1|p')
    local ENDPOINT="https://${HOST}${URI}"

    local ACCESS_KEY="${AWS_ACCESS_KEY_ID}"
    local SECRET_KEY="${AWS_SECRET_ACCESS_KEY}"
    local SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

    if [[ -z "$ACCESS_KEY" || -z "$SECRET_KEY" ]]; then
	echo "Missing AWS credentials in environment:" >&2
	echo " - AWS_ACCESS_KEY_ID" >&2
	echo " - AWS_SECRET_ACCESS_KEY" >&2
	# Not needed for this function but probably required by the AWS service
	echo " - AWS_SESSION_TOKEN" >&2
	exit 1
    fi

    # Fix for :. TODO: Make it more generic
    URI=$(printf "%s" "$URI" | sed 's/:/%3A/g;')
    local AMZ_DATE=$(date -u +"%Y%m%dT%H%M%SZ")
    local DATESTAMP=$(date -u +"%Y%m%d")
    # For debugging only
    #    AMZ_DATE="20250610T125055Z"
    #    DATESTAMP="20250610"
    local CONTENT_HASH
    if [[ -e "$PAYLOAD" ]] ; then
	CONTENT_HASH=$(cat "$PAYLOAD" | openssl dgst -sha256 -hex | sed 's/^.* //')
	cp $PAYLOAD tmp-payload.txt
    else
	CONTENT_HASH=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hex | sed 's/^.* //')
    fi
    
    local SIGNED_HEADERS
    local CANONICAL_REQUEST
    # We do not have content type, should we?
    if [[ -n "$SESSION_TOKEN" ]]; then
	SIGNED_HEADERS="host;x-amz-date;x-amz-security-token"
	#            1   2   .   4   5   6   7   8   9
	CANONICAL_REQUEST=$(
	    printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
		   "$METHOD" \
		   "$URI" \
		   "" \
		   "host:$HOST" \
		   "x-amz-date:$AMZ_DATE" \
		   "x-amz-security-token:$SESSION_TOKEN" \
		   "" \
		   "$SIGNED_HEADERS" \
		   "$CONTENT_HASH"
			 );
    else
	SIGNED_HEADERS="host;x-amz-date"
	#            1   2   .   4   5   6   7   8
	CANONICAL_REQUEST=$(
	    printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
		   "$METHOD" \
		   "$URI" \
		   "" \
		   "host:$HOST" \
		   "x-amz-date:$AMZ_DATE" \
		   "" \
		   "$SIGNED_HEADERS" \
		   "$CONTENT_HASH"
			 );
    fi
    #debug "CANONICAL_REQUEST='$CANONICAL_REQUEST'"
    local CANONICAL_REQUEST_HASH=$(printf '%s' "$CANONICAL_REQUEST" | openssl dgst -sha256 | sed 's/^.* //')
    local ALGORITHM="AWS4-HMAC-SHA256"
    local CREDENTIAL_SCOPE="$DATESTAMP/$REGION/$SERVICE/aws4_request"

    local STRING_TO_SIGN=$(
	printf '%s\n%s\n%s\n%s' \
	       "$ALGORITHM" \
	       "$AMZ_DATE" \
	       "$CREDENTIAL_SCOPE" \
	       "$CANONICAL_REQUEST_HASH"
	  )

    #debug "STRING_TO_SIGN='$STRING_TO_SIGN'"
    local K_SECRET=$(printf "%s" "AWS4$SECRET_KEY" | xxd -p -c 256)
    local K_DATE=$(HMAC "$K_SECRET" "$DATESTAMP")
    local K_REGION=$(HMAC "$K_DATE" "$REGION")
    local K_SERVICE=$(HMAC "$K_REGION" "$SERVICE")
    local K_SIGNING=$(HMAC "$K_SERVICE" "aws4_request")

    local SIGNATURE=$(printf '%s' "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$K_SIGNING" | sed 's/^.* //')

    local AUTH_HEADER="Authorization: $ALGORITHM Credential=$ACCESS_KEY/$CREDENTIAL_SCOPE, SignedHeaders=$SIGNED_HEADERS, Signature=$SIGNATURE"
    local DATE_HEADER="X-Amz-Date: $AMZ_DATE"
    local SECTOK_HEADER="X-Amz-Security-Token: $SESSION_TOKEN"
    echo "$AUTH_HEADER"
    echo "$DATE_HEADER"
    if [[ -n "$SESSION_TOKEN" ]] ; then
	echo "$SECTOK_HEADER"
    fi
}
