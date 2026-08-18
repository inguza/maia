[
  {
    "name": "pipe",
    "description": "Execute multiple tools in pipeline order, piping the output from one to the next.",
    "command": "pipe.sh",
    "instructions": [ "pipe.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "pipeline": {
	  "type": "array",
	  "items": {
            "type": "object",
            "properties": {
              "name": {
	        "type": "string",
	        "description": "Name of the function/tool to use."
              },
              "arguments": {
                "type": "object",
	        "description": "Arguments for the function/tool use."
              }
            },
            "required": [ "name", "arguments" ],
            "additionalProperties": false
          }
        }
      },
      "required": [ "pipeline" ],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "sequence",
    "description": "Execute multiple tools in sequence order.",
    "command": "sequence.sh",
    "instructions": [ "sequence.txt" ],
    "parameters": {
      "type": "object",
      "properties": {
        "sequence": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": {
	        "type": "string",
	        "description": "Name of the function/tool to use."
              },
              "arguments": {
                "type": "object",
	        "description": "Arguments for the function/tool use."
              }
            },
            "required": [ "name", "arguments" ],
            "additionalProperties": false
          }
        }
      },
      "required": [ "sequence" ],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "print",
    "description": "Print content.",
    "command": "print.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "content": {
	  "type": "string",
	  "description": "The content to print."
        }
      },
      "required": [ "content" ],
      "additionalProperties": false
    },
    "strict": true
  }
]
