map(
  select(
    ((.content // "") | test("^[[:space:]]*$") | not)
    or .tool_calls
  )
  | if .role == "system" then
      .role = "user"
      | .content = [{text: .content}]
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
      if ((.content // "") == "" and ((.files // []) | length) == 0) then
        empty
      else
        .role = "user"
        | (.files // []) as $files
        | .content = [{
            toolResult: {
              toolUseId: .tool_call_id,
              content: (
                (if (.content // "") == "" then [] else [{text: .content}] end)
                + ($files | map(select(.type != "text") |
                    if .type == "image" then
                      {image: {
                        format: (.mime | split("/")[1]),
                        source: {bytes: .base64}
                      }}
                    elif .type == "document" then
                      {document: {
                        format: (.mime | split("/")[1]),
                        name: .filename,
                        source: {bytes: .base64}
                      }}
                    else
                      {text: ("Binary file of type '" + .type + "'.")}
                    end))
              )
            }
          }]
        | del(.files, .tool_call_id)
      end
    else
      .content = [{text: .content}]
    end
)
