[
  {
    "name":"resource-discover",
    "description": "Discover resources available from resource providers.",
    "command": "resource-discover.sh",
    "inputSchema": {
      "type": "object",
      "properties": {},
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"context-resource-remember",
    "description": "Add resources to the known context.",
    "command": "resource-remember.sh",
    "instructions": [],
    "inputSchema": {
      "type": "object",
      "properties": {
        "resources": {
	  "type": "array",
          "items": {
	    "type": "string",
            "description": "Resource to add to the currently known context."
	  }
        }
      },
      "required": ["resources"],
      "additionalProperties": false
    }
  },
  {
    "name": "context-resource-forget",
    "description": "Forget resource content from the known context.",
    "command": "resource-forget.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
        "resources": {
	  "type": "array",
          "items": {
	    "type": "string",
            "description": "Resource(s) to remove from the known context. Glob pattern matching can be used to match multiple resources."
	  }
        }
      },
      "required": ["resources"],
      "additionalProperties": false
    }
  }
]
