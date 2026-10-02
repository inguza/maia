[
  {
    "name":"task-create-private",
    "description": "Create private task.",
    "command": "task-create.sh --private",
    "inputSchema": {
      "type": "object",
      "properties": {
        "description": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Task description. Multiple entries for multiple lines."
        }
      },
      "required": ["description"],
      "additionalProperties": false
    }
  },
  {
    "name":"task-create-shared",
    "description": "Create a shared task. A shared task can be used by other sessions.",
    "command": "task-create.sh --shared",
    "effects":["shared-context"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "description": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Task description. Multiple entries for multiple lines."
        }
      },
      "required": ["description"],
      "additionalProperties": false
    }
  },
  {
    "name":"task-remember",
    "description": "Remember one or more available tasks. This retrieves their current details and adds them to the current session's task context.",
    "command": "task-multiple.sh remember",
    "inputSchema": {
      "type": "object",
      "properties": {
        "tasks": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Task IDs to remember."
        }
      },
      "required": ["tasks"],
      "additionalProperties": false
    }
  },
  {
    "name":"task-forget",
    "description": "Forget a task. Do this if you do not plan to work on the task yet.",
    "command": "task-multiple.sh forget",
    "inputSchema": {
      "type": "object",
      "properties": {
        "tasks": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Task IDs to forget."
        }
      },
      "required": ["tasks"],
      "additionalProperties": false
    }
  },
  {
    "name":"task-update",
    "description": "Replace the description of a task.",
    "command": "task-update.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
        "task": {
	  "type": "string",
          "description": "Task to update."
        },
        "description": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Task description. Multiple entries for multiple lines."
        },
	"version": {
	  "type": "string",
	  "description": "Version of the task to update. Must match the latest task version."
	}
      },
      "required": ["description"],
      "additionalProperties": false
    }
  },
  {
    "name":"task-mark",
    "description": "Update the status of a task.",
    "command": "task-mark.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
        "task": {
	  "type": "string",
          "description": "Task to update the status for."
        },
	"status": {
	  "type": "string",
	  "description": "Status of the task. Any value possible but 'new', 'progress', 'done' and 'cancelled' has a special meaning."
	},
	"version": {
	  "type": "string",
	  "description": "Version of the task to update. Must match the latest task version."
	}
      },
      "required": ["task", "status", "version"],
      "additionalProperties": false
    }
  },
  {
    "name":"task-report",
    "description": "Report progress on a task.",
    "command": "task-report.sh",
    "inputSchema": {
      "type": "object",
      "properties": {
        "task": {
	  "type": "string",
          "description": "Task IDs to forget."
        },
	"progress": {
	  "type": "string",
	  "description": "Description of the progress report of a task."
	},
	"version": {
	  "type": "string",
	  "description": "Version of the task to update. Must match the latest task version."
	}
      },
      "required": ["task", "progress", "version"],
      "additionalProperties": false
    }
  }
]
