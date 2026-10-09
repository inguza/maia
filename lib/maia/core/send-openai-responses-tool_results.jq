[
  .output[]?
  | select(
      (.type | endswith("_call"))
      and .type != "function_call"
      and .status == "completed"
    )
]
| if length == 0 then null else . end
