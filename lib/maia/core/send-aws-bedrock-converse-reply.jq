[
  .output.message.content[]?
  | .text?
  | select(. != null)
]
| join("")
