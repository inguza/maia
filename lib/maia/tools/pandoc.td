[
  {
    "name":"pandoc",
    "description": "General markup converter",
    "command": "pandoc.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Input file. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"input-format": {
          "type": "string",
          "description": "Input format."
	},
	"output-format": {
          "type": "string",
          "description": "Output format."
	},
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of pandoc command line arguments. Allowed are: --quiet --list-input-formats --list-output-formats."
	}
      },
      "required": ["path"]
    },
    "strict": true
  }
]
