[
  {
    "name":"shell-exec",
    "description": "Execute bash shell commands. An execution proposal will be created. This tool cannot be used with the core-pipe tool.",
    "command": "shell-exec.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
        "commands": {
          "type": "string",
          "description": "Shell commands to execute, provided as a single shell script."
        }
      },
      "required": ["commands"],
      "additionalProperties": false
    }
  },
  {
    "name": "command-exec",
    "description":"Execute one approved external command directly from its argv. The command and all arguments are checked against execution approval rules before execution. If the invocation is not approved, a pending execution change is created instead. No caller-supplied shell script is evaluated.",
    "effects": ["limited-exec"],
    "command": "command-exec.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
        "command": {
          "type": "array",
          "items": {"type": "string"},
          "minItems": 1,
	  "description":"A non-empty flat argv array. The first element is the executable name; every remaining element is one argument. Spaces inside an element do not split it. Values such as `|` and `;` are ordinary arguments, not separators. The tool never interprets shell syntax. Path-glob expansion applies only to operands designated by a matching `%` path slot."
        }
      },
      "required": ["command"],
      "additionalProperties": false
    }
  }
]
