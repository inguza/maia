[
  {
    "name":"util-file",
    "description": "Determine file type.",
    "command": "allowed-tool.sh file -b -c --extension -i --mime --mime-type --mime-encoding -l -L -z --uncompress -Z --uncompress-noreport",
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to search for. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of file command line arguments. Allowed are: -b -c --extension -i --mime --mime-type --mime-encoding -l -L -z --uncompress -Z --uncompress-noreport."
	}
      },
      "required": ["pathspecs"],
      "additionalProperties": false
    }
  }
]
