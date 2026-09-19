[
  .output.message.content[]?
  | select(.toolUse)
  | .toolUse
  | {
      id: .toolUseId,
      type: "function",
      function: {
        name: .name,
        arguments: (.input | tojson)
      }
    }
]
| if length == 0 then null else . end
