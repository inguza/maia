[
  {
    "name": "pipe",
    "description": "Use multiple tools in sequence, piping the output from one to the next.",
    "command": "pipe.sh",
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
    "description": "Use multiple tools in sequence, executed one after the other in sequence order.",
    "command": "sequence.sh",
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
      "required": [ "pipeline" ],
      "additionalProperties": false
    },
    "strict": true
  }
]