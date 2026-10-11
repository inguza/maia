[
  .[]
  | if (.name and .description and .inputSchema) then
      {
        type: "function",
        name,
        description,
        parameters: .inputSchema
      }
    elif (.name and (.inputSchema == null) and .api_def) then
      .api_def
    else
      error("Invalid tool definition: missing required fields")
    end
]
