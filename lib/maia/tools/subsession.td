[
  {
    "name": "subsession-create",
    "description": "Create a new AI interaction subsession. A subsession inherits tool and skill context but not file context.",
    "command": "maia-subsession-create.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the subsession to create."
        }
      },
      "required": ["name"]
    },
    "strict": true
  },
  {
    "name": "subsession-show",
    "description": "Show information about a subsession.",
    "command": "maia-subsession-show.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "show": {
          "type": "string",
          "description": "Name of the subsession."
        }
      },
      "required": ["name"]
    },
    "strict": true
  },
  {
    "name": "subsession-delete",
    "description": "Remove an AI interaction subsession.",
    "command": "maia-subsession-delete.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the subsession."
        }
      },
      "required": ["name"]
    },
    "strict": true
  },
  {
    "name": "subsession-list",
    "description": "List AI interaction subsessions.",
    "command": "maia-subsession-list.sh",
    "parameters": null,
    "strict": true
  },
  {
    "name": "subsession-tool-list",
    "description": "List allowed tools for a subsesson.",
    "command": "maia-subsession-list-common.sh tool",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the subsession."
        }
      },
      "required": ["name"]
    },
    "strict": true
  },
  {
    "name": "subsession-skill-list",
    "description": "List allowed skills for a subsesson.",
    "command": "maia-subsession-list-common.sh skill",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the subsession."
        }
      },
      "required": ["name"]
    },
    "strict": true
  },
  {
    "name": "subsession-tool-restrict",
    "description": "Restrict allowed tools for a subsesson.",
    "command": "maia-subsession-restrict-common.sh tool",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the subsession."
        },
	"restrictions": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the tool to restrict. Glob wildcards are possible to use."
	  }
	}
      },
      "required": ["name", "restrictions"]
    },
    "strict": true
  },
  {
    "name": "subsession-skill-restrict",
    "description": "Restrict allowed skills for a subsesson.",
    "command": "maia-subsession-restrict-common.sh skill",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Name of the subsession."
        },
	"restrictions": {
	  "type": "array",
	  "items" : {
	    "type": "string",
	    "description": "Name of the tool to restrict. Glob wildcards are possible to use."
	  }
	}
      },
      "required": ["name", "restrictions"]
    },
    "strict": true
  },
  {
    "name": "subsession-send",
    "description": "Send a request to the LLM in a subsession.",
    "command": "maia-send.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "subsession": {
          "type": "string",
          "description": "Name of the subsession to send the request in."
        },
        "content": {
          "type": "string",
          "description": "The content to send to the LLM. If absent content is read from stdin."
        }
      },
      "required": ["subsession"]
    },
    "strict": true
  }
]
