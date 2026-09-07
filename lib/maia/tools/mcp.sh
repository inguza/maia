#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -eo pipefail

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/common.sh"

name="$1"
mcpname="$2"
shift 2
endpoint="$*"

IFS= read -r arguments <&3

jq -c -n \
    --arg name "$name" \
    --argjson arguments "$arguments" \
    '{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
            name: $name,
            arguments: $arguments
        }
    }' \
	| mcp_request "$name" "$mcpname" "$endpoint" \
	| jq -r '
	    if .result.isError then
	      "[MCP ERROR] " + (.result.content[] | select(.type == "text") | .text)
	    else
	      .result.content[] | select(.type == "text") | .text
	    end
	  '
