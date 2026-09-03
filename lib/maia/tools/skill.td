[
  {
    "name": "context-skill-remember",
    "description": "Remember a skill instruction in the current context.",
    "command": "maia-skill-remember.sh",
    "parameters": {
      "type": "object",
      "properties": {
	"skills": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Name of the skill to remember."
	  }
	}
      },
      "required": ["skills"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "context-skill-forget",
    "description": "Forget a skill instruction from the current context.",
    "command": "maia-skill-forget.sh",
    "parameters": {
      "type": "object",
      "properties": {
	"skills": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Name of the skill to forget."
	  }
	}
      },
      "required": ["skills"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "skill-exec",
    "description": "Execute a skill script with optional arguments. ONLY use this tool to execute a script explicitly mentioned in the description of the specified skill.",
    "command": "maia-skill-execute.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "skill": {
          "type": "string",
          "description": "Name of the skill to execute."
        },
        "script": {
          "type": "string",
          "description": "Path to the script executable specified by the skill."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
          "description": "Arguments to the script. Each argument should be a separate string."
	}
      },
      "required": ["skill", "script"],
      "additionalProperties": false
    },
    "strict": true
  }
]
