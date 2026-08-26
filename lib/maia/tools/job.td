[
  {
    "name": "job-start",
    "description": "Start a background job. A job id will be the output..",
    "command": "job-start.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
	  "type": "string",
	  "description": "Name of the function/tool to use."
        },
      	"arguments": {
          "type": "object",
	  "description": "Arguments for the function/tool use."
      	},
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        }	
      },
      "required": [ "name", "arguments" ],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "job-list",
    "description": "List all background jobs. Returns their job ids.",
    "command": "job-list.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        }	
      },
      "required": [],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "job-show",
    "description": "Show the metadata and current status of a background job.",
    "command": "job-id.sh show",
    "parameters": {
    "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "description": "Job id."
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        }	
      },
      "required": ["id"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "job-status",
    "description": "Show the current status of a background job: Running, Completed(0), Failed(exitcode), Killed(cause), or Missing.",
    "command": "job-id.sh status",
    "parameters": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "description": "Job id."
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        }	
      },
      "required": ["id"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "job-output",
    "description": "Show the output produced by a background job so far, including stderr. Output is available while the job is running and after it finishes.",
    "command": "job-id.sh output",
    "parameters": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "description": "Job id."
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        }	
      },
      "required": ["id"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "job-cancel",
    "description": "Cancel a running background job.",
    "command": "job-id.sh cancel",
    "parameters": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "description": "Job id."
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        }	
      },
      "required": ["id"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "job-delete",
    "description": "Delete a background job and its data. A running job cannot be deleted unless force is true.",
    "command": "job-delete.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "description": "Job id."
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        },
        "force": {
          "type": "boolean",
          "description": "Force deletion (optional)."
        }
      },
      "required": ["id"],
      "additionalProperties": false
    },
    "strict": true
  },
  {
    "name": "job-exist",
    "description": "Check whether a background job exists. Returns no output and exits successfully if the job exists, or exits with status 1 if it does not exist.",
    "command": "job-id.sh exist",
    "parameters": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "description": "Job id."
        },
        "subsession": {
          "type": "string",
          "description": "The subsession name that should remember the specified files. If absent current session is used."
        }	
      },
      "required": ["id"],
      "additionalProperties": false
    },
    "strict": true
  }
]
