#!/bin/bash

while read -r line; do
    method=$(echo "$line" | jq -r '.method' 2>/dev/null)
    id=$(echo "$line" | jq -r '.id' 2>/dev/null)
    case "$method" in
	initialize)
            echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"protocolVersion":"2024-11-05","capabilities":{"experimental":{},"prompts":{"listChanged":false},"resources":{"subscribe":false,"listChanged":false},"tools":{"listChanged":false}},"serverInfo":{"name":"math","version":"0.0.1"}}}'
	    ;;
	notifications/initialized)
            :
	    ;;
	tools/list)
            echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"tools":[{"name":"test1","description":"Test description 1 - will succeed","inputSchema":{"type":"object","properties":{}}},{"name":"test2","description":"Test description 2 - will fail","inputSchema":{"type":"object","properties":{}}},{"name":"test3","description":"Test description 3 - will give empty string","inputSchema":{"type":"object","properties":{}}}]}}'
	    ;;
	resources/list)
            echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"resources":[]}}'
	    ;;
	prompts/list)
            echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"prompts":[]}}'
	    ;;
	tools/call)
	    tool_method=$(echo "$line" | jq -r '.params.name' 2>/dev/null)
	    case "$tool_method" in
		test1)
		    echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"content":[{"type":"text","text":"Test response"}],"isError":false}}'
		    ;;
		test2)
		    echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"content":[{"type":"text","text":"Something went wrong"}],"isError":true}}'
		    ;;
		*)
		    echo ""
		    ;;
	    esac
	    ;;
	*)
            echo '{"jsonrpc":"2.0","id":'"$id"',"error":{"code":-32601,"message":"Method not found"}}'
	    ;;
    esac
done
