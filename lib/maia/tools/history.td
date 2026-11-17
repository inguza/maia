[
  {
    "name":"history-retrieve",
    "description": "Retrieve the original content of conversation history entries.",
    "command": "history-retrieve.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
	"ids": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "Conversation history item ID(s) whose original content should be retrieved."
	}
      },
      "required": ["ids"],
      "additionalProperties": false
    }
  },
  {
    "name":"history-prune-tools",
    "description": "Replace tool call output information for all tool calls with a Pruned marker.",
    "command": "history-prune-tools.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
      },
      "required": [],
      "additionalProperties": false
    }
  }
]
