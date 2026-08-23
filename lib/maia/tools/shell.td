[
  {
    "name":"shell-exec",
    "description": "Execute commands. An execution proposal will be created.",
    "command": "shell-exec.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "commands": {
          "type": "string",
          "description": "Shell commands to execute, provided as a single shell script."
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name for which to record the execution proposal. If absent current session is used."
        }
      },
      "required": ["commands"]
    },
    "strict": true
  }
]
