[
  {
    "name": "core-pipe",
    "description": "Execute multiple tools in pipeline order, piping the output from one to the next.",
    "command": "core-pipe.sh",
    "instructions": [ "basics.txt", "core-pipe.txt" ],
    "inputSchema": {
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
	        "description": "Arguments for the function/tool use.",
		"additionalProperties": true
              }
            },
            "required": [ "name", "arguments" ]
          },
	  "additionalProperties": false
        }
      },
      "required": [ "pipeline" ],
      "additionalProperties": false
    }
  },
  {
    "name": "core-sequence",
    "description": "Execute multiple tools in sequence order.",
    "command": "core-sequence.sh",
    "instructions": [ "basics.txt", "sequence.txt" ],
    "inputSchema": {
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
	        "description": "Arguments for the function/tool use.",
		"additionalProperties": true
              }
            },
            "required": [ "name", "arguments" ],
            "additionalProperties": false
          }
        }
      },
      "required": [ "sequence" ],
      "additionalProperties": false
    }
  },
  {
    "name": "core-print",
    "description": "Print content.",
    "command": "core-print.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
        "content": {
	  "type": "string",
	  "description": "The content to print. If absent, stdin is printed."
        }
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name": "core-sleep",
    "description": "Sleep for the specified duration.",
    "command": "sleep.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
        "duration": {
	  "type": "string",
	  "description": "The duration to sleep. Defaults to seconds if no suffix is specified. The suffixes s, m, h and d specify seconds, minutes, hours and days respectively. Example: 5.5s sleeps for 5.5 seconds."
        }
      },
      "required": [ "duration" ],
      "additionalProperties": false
    }
  }
]
