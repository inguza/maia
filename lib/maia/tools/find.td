[
  {
    "name":"find",
    "description": "Search files using regular expression recursively",
    "command": "find.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to search for. Only paths relative to the current directory allowed."
        },
	"mindepth": {
          "type": "string",
          "description": "Do not apply any tests or actions at levels less than levels (a non-negative integer). 1 means process all files except the starting-points."
        },
        "maxdepth": {
          "type": "string",
          "description": "Descend at most levels (a non-negative integer) levels of directories below the starting-points. 0 means only apply the tests and actions to the starting-points themselves."
        },
        "name": {
          "type": "string",
          "description": "File name matches shell pattern pattern."
        },
        "type": {
          "type": "string",
          "description": "File is of type: d - directory, f - regular file."
        },
        "path": {
          "type": "string",
          "description": "Path name matches shell pattern pattern."
        },
        "ipath": {
          "type": "string",
          "description": "Path name matches shell pattern pattern, case insensitive."
        },
	"arguments": {
          "type": "string",
          "description": "Space separated options. Allowed options are (executable, writable)"
	}
      },
      "required": ["pathspec"]
    },
    "strict": true
  },
  {
    "name":"ls",
    "description": "List files",
    "command": "ls.sh",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to search for. Only paths relative to the current directory allowed. Current directory (.) if not specified."
        }
      },
      "required": []
    },
    "strict": true
  }
]
