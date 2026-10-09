[
  .[]
  | select(.inputSchema != null)
  | if (.name and .description) then
      {
        type: "function",
        function: (
          {
            name,
            description,
	    parameters: .inputSchema
          }
        )
     }
    else
      error("Invalid json")
    end
]
