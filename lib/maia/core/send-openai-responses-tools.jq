[
  .[]
  | if (.name and .description and .inputSchema) then
      {
        type: "function",
        name,
        description,
        parameters: .inputSchema
      }
    elif (.name and (.inputSchema == null) and .api_type) then
      { type: .api_type }
    else
      error("Invalid tool definition: missing required fields")
    end
]
