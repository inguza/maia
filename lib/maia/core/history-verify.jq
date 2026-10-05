. as $messages
  |
  # Hidden entries are not visible to the LLM, so they are absent for the
  # purpose of both consistency checks.
  # Report visible tool responses that do not belong to an earlier visible
  # assistant call.
  (range(0; length)
   | select($messages[.].hidden != true and $messages[.].role == "tool")
   | . as $i
   | $messages[$i] as $tool
   | select(
       (
         $messages[:$i]
         | map(select(.hidden != true
                      and .role == "assistant"
                      and (.tool_calls? | type) == "array"))
         | map(.tool_calls[]?.id)
         | index($tool.tool_call_id)
       ) == null
     )
   | {
       problem: "orphan_tool_response",
       timestamp: $tool.timestamp,
       id: $tool.id,
       tool_call_id: $tool.tool_call_id
     })
  ,
  # Report visible assistant tool calls for which no later visible tool
  # response exists. This catches an interrupted send where Ctrl-C occurred
  # before the tool response messages were persisted.
  (range(0; length)
   | . as $i
   | $messages[$i] as $assistant
   | select($assistant.hidden != true
            and $assistant.role == "assistant"
            and ($assistant.tool_calls? | type) == "array")
   | $assistant.tool_calls[] as $call
   | select(
       ($messages[($i + 1):]
        | map(select(.hidden != true
                    and .role == "tool"
                    and .tool_call_id == $call.id))
        | length) == 0
     )
   | {
       problem: "missing_tool_response",
       timestamp: $assistant.timestamp,
       id: $assistant.id,
       tool_call_id: $call.id
     })
