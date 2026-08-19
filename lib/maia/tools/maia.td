[
  {
    "name":"maia-file-remember",
    "description": "Remember/add a file to the known context",
    "command": "maia-file-remember.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "filepattern": {
          "type": "string",
          "description": "File(s) to add to the currently known context. Shell file pattern matching can be used."
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
    "name": "maia-file-forget",
    "description": "Forget file content from the known context.",
    "command": "maia-file-forget.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "filepattern": {
          "type": "string",
          "description": "File(s) to remove from the currently known context. Shell file pattern matching can be used."
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
    "name": "maia-tool-list",
    "description": "List available tools.",
    "command": "maia-file-forget.sh",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    },
    "strict": true
  },
  {
    "name": "maia-change-apply",
    "description": "Apply one or more change requests to the workspace. This circumvent write permission problems from file operations. Before applying, verify that the proposed change match the intended update. This modifies the actual files.",
    "command": "maia-change-apply.sh",
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
    "name": "maia-subsession-create",
    "description": "Create a new AI interaction subsession.",
    "command": "maia-subsession-create.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the subsession to create."
        }
      },
      "required": ["name"]
    },
    "strict": true
  },
  {
    "name": "maia-subsession-show",
    "description": "Show information about a subsession.",
    "command": "maia-subsession-show.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "show": {
          "type": "string",
          "description": "Name of the subsession to delete."
        }
      },
      "required": ["name"]
    },
    "strict": true
  },
  {
    "name": "maia-subsession-delete",
    "description": "Remove an AI interaction subsession.",
    "command": "maia-subsession-delete.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the subsession to delete."
        }
      },
      "required": ["name"]
    },
    "strict": true
  },
  {
    "name": "maia-subsession-list",
    "description": "List AI interaction subsessions.",
    "command": "maia-subsession-list.sh",
    "parameters": null,
    "strict": true
  },
  {
    "name": "maia-send",
    "description": "Send a request to the LLM in a subsession.",
    "command": "maia-send.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession to send the request in."
        },
        "content": {
          "type": "string",
          "description": "The content to send to the LLM. If absent content is read from stdin (to be used with pipes)."
        }
      },
      "required": ["subsession"]
    },
    "strict": true
  }
]
