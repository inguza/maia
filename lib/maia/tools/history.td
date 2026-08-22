[
  {
    "name":"context-history-retrieve",
    "description": "Retrieve the original content of conversation history entries.",
    "command": "history-retrieve.sh",
    "parameters": {
      "type": "object",
      "properties": {
	"ids": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Identity of a conversation history entry whose original content should be retrieved."
	  }
	},
        "subsession": {
          "type": "string",
          "description": "The subsession from which to retrieve the conversation history entries."
        }
      },
      "required": ["ids"]
    },
    "strict": true
  }
]
