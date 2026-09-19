map(
  select(
    ((.content // "") | test("^[[:space:]]*$") | not)
    or .tool_calls
  )
  | if .role == "system" then
      .role = "user"
    elif .role == "assistant" and .tool_calls then
      .content = [
        .tool_calls[] |
        {
          toolUse: {
            toolUseId: .id,
            name: .function.name,
            input: (.function.arguments | fromjson)
          }
        }
      ]
    elif .role == "tool" then
      .role = "user"
      | .content = [{
          toolResult: {
            toolUseId: .tool_call_id,
            content: [{text: .content}]
          }
        }]
    else
      .content = [{text: .content}]
    end
)
