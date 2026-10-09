[
  .[]
  | select(.inputSchema != null)
  | if (.name and .description and .inputSchema) then
      {
        toolSpec: {
	  name: .name,
	  description: .description,
	  inputSchema: {
	    json: .inputSchema
	  }
	}
      }
    else
      error("Invalid tool definition: missing required fields")
    end
]
