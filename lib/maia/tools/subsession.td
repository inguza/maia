[
  {
    "name": "subsession-create",
    "description": "Create a new AI interaction subsession.",
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
          "description": "Name of the subsession to delete."
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
          "description": "Name of the subsession to delete."
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
