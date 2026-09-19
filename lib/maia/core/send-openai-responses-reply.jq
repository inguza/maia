[.output[]?
  | select(.type == "message")
  | .content[]?
  | select(.type == "output_text")
  | .text]
  | join("")
