[
  {
    "name": "core-pipe",
    "description": "Execute multiple tools in pipeline order, piping the output from one to the next.",
    "command": "pipe.sh",
    "instructions": [ "basics.txt", "pipe.txt" ],
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
    "name": "core-sequence",
    "description": "Execute multiple tools in sequence order.",
    "command": "sequence.sh",
    "instructions": [ "basics.txt", "sequence.txt" ],
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
    "name": "core-print",
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
  },
  {
    "name": "core-sleep",
    "description": "Sleep for the specified duration.",
    "command": "sleep.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "duration": {
	  "type": "string",
	  "description": "The duration to sleep. Defaults to seconds if no suffix is specified. The suffixes s, m, h and d specify seconds, minutes, hours and days respectively. Example: 5.5s sleeps for 5.5 seconds."
        }
      },
      "required": [ "time" ],
      "additionalProperties": false
    },
    "strict": true
  }
]
