def openai_file_type:
  if . == "image" then "image"
  elif . == "other" then "file"
  elif . == "document" then "file"
  elif . == "text" then "text"
  elif . == "audio" then "audio"
  else .
  end;

def file_content:
  (.files // [])
  | map(select(.type != "text") |
      (if .type == "image" then
        {
          type: "input_image",
          detail: (.quality // null),
          image_url: (.url // ("data:" + .mime + ";base64," + .base64))
        }
      elif .type == "document" then
        {
          type: "input_file",
          filename: .filename,
          detail: (.quality // null)
        }
        + (if ((.base64 // "") != "") then
             {file_data: ("data:" + .mime + ";base64," + .base64)}
           elif ((.url // "") != "") then
             {file_url: .url}
           else
             {}
           end)
      else
        {
          type: ("input_" + (.type | openai_file_type)),
          filename: .filename,
          file_data: ("data:" + .mime + ";base64," + .base64)
        }
      end)
      | if .detail == null then del(.detail) else . end
    );

map(
  if .role == "tool" then
    if ((.content // "") == "" and ((.files // []) | length) == 0) then
      []
    else
      {
        type: "function_call_output",
        call_id: .tool_call_id,
        output: (
          (if (.content // "") == "" then [] else [{type: "input_text", text: .content}] end)
          + file_content
        )
      }
    end
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
