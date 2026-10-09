[
  .output[]?
  | select( .type == "reasoning" )
]
| if length == 0 then null else . end
