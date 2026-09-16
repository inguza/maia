. as $messages
| $messages
| to_entries
| map(
    . as $entry
    | if .value.role == "tool"
         and (
           $messages[:$entry.key]
           | map(select(.role == "assistant" and .tool_calls))
           | map(.tool_calls[]?.id)
           | index($entry.value.tool_call_id)
         ) == null
      then
        .value + {
          hidden: true,
          call_pruned: true
        }
      else
        .value
      end
  )
