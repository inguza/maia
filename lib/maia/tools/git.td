[
  {
    "name":"git-status",
    "description": "Git status.",
    "command": "git-status.sh -s --short -b --branch",
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to check the status for. Only paths relative to the current directory allowed. If absent the status of the current directory is shown."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -s --short -b --branch."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-log",
    "description": "Git log.",
    "command": "git-log.sh --no-decorate --source",
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to check the status for. Only paths relative to the current directory allowed. If absent current directory is logged."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: --no-decorate --source."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-show",
    "description": "Git show.",
    "command": "git-show.sh --abbrev-commit --oneline",
    "inputSchema": {
      "type": "object",
      "properties": {
        "objects": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Objects to show. If absent the last commit is shown."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: --abbrev-commit --oneline."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  }
]
