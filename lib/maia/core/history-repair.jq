. as $messages
| $messages
| to_entries
| map(
    . as $entry
    | if .value.hidden != true
         and .value.role == "assistant"
         and (.value.tool_calls? | type) == "array" then
        # Hidden entries are not sent to the LLM and must not participate in
        # repair. Keep only calls with a matching *visible* later response.
        ([
          .value.tool_calls[] as $call
          | select(
              ($messages[($entry.key + 1):]
               | map(select(.hidden != true
                            and .role == "tool"
                            and .tool_call_id == $call.id))
               | length) > 0
            )
          | $call
        ]) as $valid_calls
        | if (($valid_calls | length) == (.value.tool_calls | length)) then
            .value
          else
            (.value
             | if ($valid_calls | length) > 0
               then .tool_calls = $valid_calls
               else del(.tool_calls)
               end
             | .call_pruned = true
             | if (($valid_calls | length) == 0 and (.content == null or .content == ""))
               then .hidden = true
               else .
               end)
          end
      elif .value.hidden != true
         and .value.role == "tool"
         and (
           $messages[:$entry.key]
           | map(select(.hidden != true
                       and .role == "assistant"
                       and (.tool_calls? | type) == "array"))
           | map(.tool_calls[]?.id)
           | index($entry.value.tool_call_id)
         ) == null
      then
        # Also hide visible tool responses whose visible assistant call is
        # missing. Hidden responses are already absent from the LLM view.
        .value + {
          hidden: true,
          call_pruned: true
        }
      else
        .value
      end
  )
