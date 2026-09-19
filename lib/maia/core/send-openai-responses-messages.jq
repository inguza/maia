map(
  if .role == "tool" then
    {
      type: "function_call_output",
      call_id: .tool_call_id,
      output: .content
    }
  elif .role == "assistant" and (.tool_calls // null) != null then
    [
      {
        type: "message",
        role: "assistant",
        content: (
          if (.content // "") == "" then []
          else [{type: "output_text", text: .content}]
          end
        )
      }
    ] +
    (
      .tool_calls | map({
        type: "function_call",
        call_id: .id,
        name: .function.name,
        arguments: .function.arguments
      })
    )
  elif .role == "assistant" then
    {
      type: "message",
      role: .role,
      content: (
        if (.content // "") == "" then
	   []
        else
	   [{type: "output_text", text: .content}]
        end
      )
    }  
  else
    {
      type: "message",
      role: .role,
      content: (
        if (.content // "") == "" then
	   []
        else
	   [{type: "input_text", text: .content}]
        end
      )
    }
  end
)
| flatten
