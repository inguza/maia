[
  {
    "name":"file-write",
    "description": "Write content to a file. If the file does not exist, it is created. If the file already exists, a change proposal is created instead and the file is not modified.",
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
    "description": "Update an existing file. Always creates a change proposal.",
    "command": "file-change.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "File to update."
        },
	"changes": {
	  "type": "array",
	  "description": "Changes to apply. Each change must match exactly one contiguous region of the current file.",
	  "items": {
	    "type": "object",
	    "properties": {
	      "old": {
	        "type": "string",
		"description": "Exact contiguous text to replace."
	      },
	      "new": {
	        "type": "string",
		"description": "Text that replaces the removed text."
	      }
	    },
	    "required": ["old", "new"],
	    "additionalProperties": false
	  }
	}
      },
      "required": ["path", "changes"]
    },
    "strict": true
  }
]
