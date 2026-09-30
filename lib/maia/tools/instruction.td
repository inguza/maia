[
  {
    "name": "context-instruction-remember",
    "description": "Remember a instruction instruction in the current context.",
    "command": "instruction-remember.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
	"instructions": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Name of the instruction to remember."
	  }
	}
      },
      "required": ["instructions"],
      "additionalProperties": false
    }
  },
  {
    "name": "context-instruction-forget",
    "description": "Forget a instruction instruction from the current context.",
    "command": "instruction-forget.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
	"instructions": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Name of the instruction to forget."
	  }
	}
      },
      "required": ["instructions"],
      "additionalProperties": false
    }
  }
]
