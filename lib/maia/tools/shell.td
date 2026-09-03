[
  {
    "name":"shell-exec",
    "description": "Execute bash shell commands. An execution proposal will be created. This tool cannot be used with the core-pipe tool.",
    "command": "shell-exec.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "commands": {
          "type": "string",
          "description": "Shell commands to execute, provided as a single shell script."
        }
      },
      "required": ["commands"],
      "additionalProperties": false
    },
    "strict": true
  }
]
