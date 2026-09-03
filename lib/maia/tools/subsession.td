[
  {
    "name": "subsession-create",
    "description": "Create a new AI interaction subsession. A subsession inherits most tool and skill context, but not file context.",
    "command": "maia-subsession-create.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession to create."
        }
      },
      "required": ["subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-show",
    "description": "Show information about a subsession.",
    "command": "maia-subsession-show.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession to show."
        }
      },
      "required": ["subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-delete",
    "description": "Remove an AI interaction subsession.",
    "command": "maia-subsession-delete.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession to delete."
        }
      },
      "required": ["subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-list",
    "description": "List all AI interaction subsessions.",
    "command": "maia-subsession-list.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": null,
    "strict": true
  },
  {
    "name": "subsession-tool-list",
    "description": "List allowed tools for a subsession.",
    "command": "maia-subsession-list-common.sh tool",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession for which to list the allowed tools."
        }
      },
      "required": ["subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-skill-list",
    "description": "List allowed skills for a subsession.",
    "command": "maia-subsession-list-common.sh skill",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession for which to list the allowed skills."
        }
      },
      "required": ["subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-tool-restrict",
    "description": "Restrict tools for a subsession. If a tool is both allowed and restricted, the most recent operation takes precedence.",
    "command": "maia-subsession-restrict-common.sh tool",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession for which to restrict tools."
        },
	"restrictions": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the tool to restrict. Glob patterns can be used to match tools."
	  }
	}
      },
      "required": ["subsession", "restrictions"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-skill-restrict",
    "description": "Restrict skills for a subsession. If a skill is both allowed and restricted, the most recent operation takes precedence.",
    "command": "maia-subsession-restrict-common.sh skill",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession for which to restrict skills."
        },
	"restrictions": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the skill to restrict. Glob patterns can be used to match skills."
	  }
	}
      },
      "required": ["subsession", "restrictions"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-tool-allow",
    "description": "Allow tools for a subsession. If a tool is both allowed and restricted, the most recent operation takes precedence.",
    "command": "maia-subsession-allow-common.sh tool",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession for which to allow tools."
        },
	"allow": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the tool to allow. Glob patterns can be used to match tools."
	  }
	}
      },
      "required": ["subsession", "allow"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-skill-allow",
    "description": "Allow skills for a subsession. If a skill is both allowed and restricted, the most recent operation takes precedence.",
    "command": "maia-subsession-allow-common.sh skill",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession for which to allow skills."
        },
	"allow": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the skill to allow. Glob patterns can be used to match skills."
	  }
	}
      },
      "required": ["subsession", "allow"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-skill-remember",
    "description": "Make a subsession remember a skill instruction.",
    "command": "maia-skill-remember.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
	"skills": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Name of the skill to remember. Glob patterns can be used to match allowed skills."
	  }
	},
        "subsession": {
          "type": "string",
          "description": "Name of the subsession that should remember the specified skill."
        }
      },
      "required": ["skills", "subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-skill-forget",
    "description": "Make a subsession forget a skill instruction.",
    "command": "maia-skill-forget.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
	"skills": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Name of the skill to forget. Glob patterns can be used to match skills."
	  }
	},
        "subsession": {
          "type": "string",
          "description": "Name of the subsession that should forget the specified skill."
        }
      },
      "required": ["skills", "subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name":"subsession-file-remember",
    "description": "Make a subsession remember file content.",
    "command": "maia-file-remember.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "files": {
	  "type": "array",
          "items": {
	    "type": "string",
            "description": "File(s) to add to the known context. Glob pattern matching can be used to match files."
	  }
        },
        "linestart": {
          "type": "string",
          "description": "If the whole file is not needed, specify the number of the first line to remember."
        },
        "lineend": {
          "type": "string",
          "description": "If the whole file is not needed, specify the number of the last line to remember."
        },
        "subsession": {
          "type": "string",
          "description": "Name of the subsession whose known context should be modified."
        }
      },
      "required": ["files", "subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-file-forget",
    "description": "Make a subsession forget file content.",
    "command": "maia-file-forget.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "files": {
	  "type": "array",
          "items": {
	    "type": "string",
            "description": "File(s) to remove from the subsessions known context. Glob patterns can be used to match files."
	  }
        },
        "subsession": {
          "type": "string",
          "description": "Name of the subsession whose known context should be modified."
        }
      },
      "required": ["files", "subsession"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "subsession-send",
    "description": "Send a message to a subsession.",
    "command": "maia-send.sh",
    "instructions": [ "subsession.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession to receive the message."
        },
        "content": {
          "type": "string",
          "description": "The content of the message to send. If omitted, content is read from stdin."
        }
      },
      "required": ["subsession"],
      "additionalProperties": false
    },
    "strict": true
  }
]
