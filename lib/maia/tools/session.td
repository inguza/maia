[
  {
    "name": "session-create",
    "description": "Create a new AI interaction session. A session inherits most tool and skill context, but not file context.",
    "command": "session-create.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session to create."
        },
	"profile": {
	  "type": "string",
          "description": "Optional configuration profile for the session. Only specify this when the profile has been explicitly requested. Use the exact profile name; never invent, guess, or derive a profile name."
	}
      },
      "required": ["session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-show",
    "description": "Show information about a session.",
    "command": "session-show.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session to show."
        }
      },
      "required": ["session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-delete",
    "description": "Remove an AI interaction session.",
    "command": "session-delete.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session to delete."
        }
      },
      "required": ["session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-list",
    "description": "List all AI interaction sessions.",
    "command": "session-list.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {},
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name": "session-tool-list",
    "description": "List allowed tools for a session.",
    "command": "session-list-common.sh tool",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session for which to list the allowed tools."
        }
      },
      "required": ["session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-skill-list",
    "description": "List allowed skills for a session.",
    "command": "session-list-common.sh skill",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session for which to list the allowed skills."
        }
      },
      "required": ["session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-tool-restrict",
    "description": "Restrict tools for a session. If a tool is both allowed and restricted, the most recent operation takes precedence.",
    "command": "session-restrict-common.sh tool",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session for which to restrict tools."
        },
	"restrictions": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the tool to restrict. Glob patterns can be used to match tools."
	  }
	}
      },
      "required": ["session", "restrictions"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-skill-restrict",
    "description": "Restrict skills for a session. If a skill is both allowed and restricted, the most recent operation takes precedence.",
    "command": "session-restrict-common.sh skill",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session for which to restrict skills."
        },
	"restrictions": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the skill to restrict. Glob patterns can be used to match skills."
	  }
	}
      },
      "required": ["session", "restrictions"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-tool-allow",
    "description": "Allow tools for a session. If a tool is both allowed and restricted, the most recent operation takes precedence.",
    "command": "session-allow-common.sh tool",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session for which to allow tools."
        },
	"allow": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the tool to allow. Glob patterns can be used to match tools."
	  }
	}
      },
      "required": ["session", "allow"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-skill-allow",
    "description": "Allow skills for a session. If a skill is both allowed and restricted, the most recent operation takes precedence.",
    "command": "session-allow-common.sh skill",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session for which to allow skills."
        },
	"allow": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the skill to allow. Glob patterns can be used to match skills."
	  }
	}
      },
      "required": ["session", "allow"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-skill-remember",
    "description": "Make a session remember a skill instruction.",
    "command": "skill-remember.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
	"skills": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Name of the skill to remember. Glob patterns can be used to match allowed skills."
	  }
	},
        "session": {
          "type": "string",
          "description": "Name of the session that should remember the specified skill."
        }
      },
      "required": ["skills", "session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-skill-forget",
    "description": "Make a session forget a skill instruction.",
    "command": "skill-forget.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
	"skills": {
	  "type": "array",
	  "items": {
	    "type": "string",
            "description": "Name of the skill to forget. Glob patterns can be used to match skills."
	  }
	},
        "session": {
          "type": "string",
          "description": "Name of the session that should forget the specified skill."
        }
      },
      "required": ["skills", "session"],
      "additionalProperties": false
    }
  },
  {
    "name":"session-file-remember",
    "description": "Make a session remember file content.",
    "command": "file-remember.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
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
        "session": {
          "type": "string",
          "description": "Name of the session whose known context should be modified."
        }
      },
      "required": ["files", "session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-file-forget",
    "description": "Make a session forget file content.",
    "command": "file-forget.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "files": {
	  "type": "array",
          "items": {
	    "type": "string",
            "description": "File(s) to remove from the sessions known context. Glob patterns can be used to match files."
	  }
        },
        "session": {
          "type": "string",
          "description": "Name of the session whose known context should be modified."
        }
      },
      "required": ["files", "session"],
      "additionalProperties": false
    }
  },
  {
    "name":"session-resource-remember",
    "description": "Make a session remember resource content.",
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
        },
        "session": {
          "type": "string",
          "description": "Name of the session whose known context should be modified."
        }
      },
      "required": ["resources", "session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-resource-forget",
    "description": "Make a session forget resource content.",
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
        },
        "session": {
          "type": "string",
          "description": "Name of the session whose known context should be modified."
        }
      },
      "required": ["resources", "session"],
      "additionalProperties": false
    }
  },
  {
    "name": "session-send",
    "description": "Send a message to a session.",
    "command": "session-send.sh",
    "instructions": [ "session.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "session": {
          "type": "string",
          "description": "Name of the session to receive the message."
        },
        "content": {
          "type": "string",
          "description": "The content of the message to send. If omitted, content is read from stdin."
        }
      },
      "required": ["session"],
      "additionalProperties": false
    }
  }
]
