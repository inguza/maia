[
  {
    "name":"util-file",
    "description": "Determine file type.",
    "command": "allowed-tool.sh file -b -c --extension -i --mime --mime-type --mime-encoding -l -L -z --uncompress -Z --uncompress-noreport",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to search for. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
	  "type": "string",
	  "description": "Space separated list of file command line arguments. Allowed are: -b -c --extension -i --mime --mime-type --mime-encoding -l -L -z --uncompress -Z --uncompress-noreport."
	}
      },
      "required": ["pathspec"],
      "additionalProperties": false
    },
    "strict": true
  }
]
