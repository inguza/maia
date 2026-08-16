[
  {
    "name":"curl",
    "description": "Tool for transferring data from or to a server.",
    "command": "curl.sh -i -D -G --get --raw -s -S -X POST",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": ""
        },
	"header": {
	  "type": "array",
          "items": {
	    "type": "string",
	    "description": "header/@file"
	  }
	},
	"data": {
	  "type": "array",
          "items": {
	    "type": "string",
	    "description": "POST data. @file reads data from a file."
	  }
	},
	"data-raw": {
	  "type": "array",
          "items": {
	    "type": "string",
	    "description": "POST data."
	  }
	},
	"data-binary": {
	  "type": "array",
          "items": {
	    "type": "string",
	    "description": "POST data as is."
	  }
	},
	"json": {
	  "type": "string",
	  "description": "Sends the specified JSON data in a POST request to the HTTP server."
	},
	"arguments": {
	  "type": "string",
	  "description": "Space separated list of file command line arguments. Allowed are: -i -D -G --get --raw -s -Sx -X POST."
	}
      },
      "required": ["url"]
    },
    "strict": true
  }
]
