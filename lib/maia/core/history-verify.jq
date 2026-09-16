. as $messages
  | range(0; length)
  | select($messages[.].role == "tool")
  | . as $i
  | $messages[$i] as $tool
  | select(
      (
        $messages[:$i]
        | map(select(.role == "assistant" and .tool_calls))
        | map(.tool_calls[]?.id)
        | index($tool.tool_call_id)
      ) == null
    )
  | {
      timestamp: $tool.timestamp,
      id: $tool.id,
      tool_call_id: $tool.tool_call_id
    }
