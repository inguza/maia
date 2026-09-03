[
  {
    "name":"jq",
    "description": "Run jq",
    "command": "jq.sh",
    "parameters": {
      "type": "object",
      "properties": {
	"arguments": {
	  "type": "array",
          "items": {
	    "type": "string"
	  },
	  "description": "Run jq. arguments contains jq command-line arguments: [options] filter [files...]. The first non-option argument is the jq filter; following arguments are input files. File path wildcards may be used. Allowed options are: -s, --slurp, --raw-input, -R, --null-input, -n, -c, --compact-output, -e, -f <file>--stream, --tab, --sort-keys, -S, -r, --raw-output, --arg <name> <value>, --argjson <name> <json>,  --slurpfile <name> <file>, --argfile <name> <file>, --args ..., --jsonargs ...."
	}
      },
      "required": ["arguments"],
      "additionalProperties": false
    },
    "strict": true
  }
]
