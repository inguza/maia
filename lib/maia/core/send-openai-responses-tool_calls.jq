[
  .output[]?
  | select(.type == "function_call")
  |
    {
      id: .call_id,
      type: "function",
      function: {
        name: .name,
        arguments: .arguments
      }
    }
]
| if length == 0 then null else . end
