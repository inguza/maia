[
  {
    "name":"pandoc",
    "description": "Convert documents between markup formats using pandoc.",
    "command": "pandoc.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Path to the input file. If omitted, content is read from stdin."
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
	  "description": "Optional pandoc command line arguments. Allowed are: --quiet, --list-input-formats, --list-output-formats."
	}
      },
      "required": [],
      "additionalProperties": false
    },
    "strict": true
  }
]
