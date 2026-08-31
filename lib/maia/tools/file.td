[
  {
    "name":"file-write",
    "description": "Write content to a file. If the file does not exist, it is created. If the file already exists, a change proposal is created instead and the file is not modified.",
    "command": "file-write.sh",
    "instructions": [ "file.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "File to write to."
        },
	"content": {
	  "type": "string",
	  "description": "The full content to write to the file. If absent data is read from stdin."
	}
      },
      "required": ["path"]
    },
    "strict": true
  },
  {
    "name":"file-append",
    "description": "Append content to the end of a file. The file is modified directly and no change proposal is created.",
    "command": "file-append.sh",
    "instructions": [ "file.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "File to append to."
        },
	"content": {
	  "type": "string",
	  "description": "The content to write to the file. If absent data is read from stdin."
	}
      },
      "required": ["path"]
    },
    "strict": true
  },
  {
    "name":"file-change",
    "description": "Update an existing file by making exact literal text replacements. Always creates a change proposal.",
    "command": "file-change.sh",
    "instructions": [ "file.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "File to update."
        },
	"changes": {
	  "type": "array",
	  "description": "A list of exact text replacements. Each change replaces one exact, contiguous region of the current file.",
	  "items": {
	    "type": "object",
	    "properties": {
	      "existing": {
	        "type": "string",
		"description": "The exact text currently present in the file. Matching is literal; whitespace and every other character matter. The text must occur exactly once in the current file."
	      },
	      "replacement": {
	        "type": "string",
		"description": "The exact text to insert in place of `existing`. All other file content remains unchanged."
	      }
	    },
	    "required": ["existing", "replacement"],
	    "additionalProperties": false
	  }
	}
      },
      "required": ["path", "changes"]
    },
    "strict": true
  },
  {
    "name":"context-file-remember",
    "description": "Remember/add a file to the known context",
    "command": "maia-file-remember.sh",
    "instructions": [ "context-file-remember.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "filepatterns": {
	  "type": "array",
          "items": {
	    "type": "string",
            "description": "File(s) to add to the currently known context. Shell file pattern matching can be used."
	  }
        },
        "linestart": {
          "type": "string",
          "description": "If the whole file is not needed, specify from what line to start remembering the file."
        },
        "lineend": {
          "type": "string",
          "description": "If the whole file is not needed, specify from what line to start remembering the file."
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        }
      },
      "required": ["filepattern"]
    },
    "strict": true
  },
  {
    "name": "context-file-forget",
    "description": "Forget file content from the known context.",
    "command": "maia-file-forget.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "filepatterns": {
	  "type": "array",
          "items": {
	    "type": "string",
            "description": "File(s) to remove from the currently known context. Shell file pattern matching can be used."
	  }
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name that should forget the specified files. If absent current session is used."
        }
      },
      "required": ["filepattern"]
    },
    "strict": true
  },
  {
    "name": "change-apply",
    "description": "Applies one or more change proposals. This circumvent write permission problems from file operations. Before applying, verify that the proposed change match the intended update. This modifies the actual files.",
    "command": "maia-change-apply.sh",
    "instructions": [ "change-apply.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
	"id": {
	  "type": "array",
          "items": {
	    "type": "string",
	    "description": "Change identities to apply in order."
	  }
	}
      },
      "required": ["id"]
    },
    "strict": true
  },
  {
    "name": "change-skip",
    "description": "Skip (reject) one or more change proposals.",
    "command": "maia-change-skip.sh",
    "parameters": {
      "type": "object",
      "properties": {
	"id": {
	  "type": "array",
          "items": {
	    "type": "string",
	    "description": "Change identities to skip in order."
	  }
	}
      },
      "required": ["id"]
    },
    "strict": true
  },
  {
    "name": "change-revert",
    "description": "Revert one or more changes.",
    "command": "maia-change-revert.sh",
    "parameters": {
      "type": "object",
      "properties": {
	"id": {
	  "type": "array",
          "items": {
	    "type": "string",
	    "description": "Change identities to revert in order."
	  }
	}
      },
      "required": ["id"]
    },
    "strict": true
  }
]
