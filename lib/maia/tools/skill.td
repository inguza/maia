[
  {
    "name": "context-skill-remember",
    "description": "Remember a skill instruction.",
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
	},
        "subsession": {
          "type": "string",
          "description": "The subsession that should remember the specified skill. If absent current session is used."
        }
      },
      "required": ["skills"]
    },
    "strict": true
  },
  {
    "name": "context-skill-forget",
    "description": "Forget a skill instruction.",
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
	},
        "subsession": {
          "type": "string",
          "description": "The subsession that should remember the specified skill. If absent current session is used."
        }
      },
      "required": ["skills"]
    },
    "strict": true
  },
  {
    "name": "skill-exec",
    "description": "Execute a skill script with optional arguments. This shall ONLY be used to execute scripts mentioned for a specific skill description.",
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
          "description": "Path to the script executable."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
          "description": "Arguments to the script. Each argument should be a separate string."
	}
      },
      "required": ["skill", "script"]
    },
    "strict": true
  }
]
