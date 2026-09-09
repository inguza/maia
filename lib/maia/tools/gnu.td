[
  {
    "name":"util-grep",
    "description": "Search files using regular expression.",
    "command": "util-grep.sh -R -E -F -G -i -v -w -x -c -s -n -a -I --",
    "inputSchema": {
      "type": "object",
      "properties": {
        "searchpattern": {
          "type": "string",
          "description": "Regular expression to search for."
        },
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to search in. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"after-context": {
	  "type": "string",
	  "description": "Print before-context number of lines of trailing context after matching lines."
	},
	"before-context": {
	  "type": "string",
	  "description": "Print before-context number of lines of leading context before matching lines."
	},
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of grep command line arguments. Allowed are: -R -E -F -G -i -v -w -x -c -s -n -a -I --."
	}
      },
      "required": ["searchpattern"],
      "additionalProperties": false
    }
  },
  {
    "name":"util-find",
    "description": "Search files - but not files starting with a .",
    "command": "util-find.sh -d -depth -executable -nogroup -nouser -readable -ls",
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to search for. Only paths relative to the current directory allowed."
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
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of find command line arguments. Allowed are: -d -depth -executable -nogroup -nouser -readable -ls."
	}
      },
      "required": ["pathspecs"],
      "additionalProperties": false
    }
  },
  {
    "name":"util-ls",
    "description": "List files",
    "command": "allowed-tool.sh ls -B -l --time-style=long-iso -d -f -G -h -o -t -r -U -1 --",
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to list. Only paths relative to the current directory allowed."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of ls command line arguments. Allowed are: -B -l --time-style=long-iso -d -f -G -h -o -t -r -U -1 --"
	}
      },
      "required": ["pathspecs"],
      "additionalProperties": false
    }
  },
  {
    "name":"util-sort",
    "description": "List files",
    "command": "allowed-tool.sh sort -n -s -v --show-nonprinting --",
    "inputSchema": {
      "type": "object",
      "properties": {
        "filespecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files to sort. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of sort command line arguments. Allowed are: -n -s -v --show-nonprinting --."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"util-cat",
    "description": "Print the content of one or more concatenated files",
    "command": "allowed-tool.sh cat --",
    "instructions": [ "util-cat.txt" ],
    "inputSchema": {
      "type": "object",
      "properties": {
        "filespecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files to print the content of. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of cat command line arguments. Allowed are: --."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"util-head",
    "description": "Output the first part of files",
    "command": "head-tail.sh head --",
    "inputSchema": {
      "type": "object",
      "properties": {
        "filespecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files to print the head for. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"lines": {
          "type": "string",
          "description": "Print the first <lines> lines instead of the first 10."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"util-tail",
    "description": "Output the last part of files",
    "command": "head-tail.sh tail --",
    "inputSchema": {
      "type": "object",
      "properties": {
        "filespecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files to print the tail of. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"lines": {
          "type": "string",
          "description": "Print the last <lines> lines instead of the last 10."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"util-wc",
    "description": "Count newline, word and bytes for files",
    "command": "allowed-tool.sh wc -c --bytes -m --chars -l --lines -w --words --",
    "inputSchema": {
      "type": "object",
      "properties": {
        "filespecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files to count in. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of wc command line arguments. Allowed are: -c --bytes -m --chars -l --lines -w --words --."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"util-sed",
    "description": "Stream editor - write forbidden",
    "command": "util-sed.sh --posix -s -E -r --regexp-extended --",
    "inputSchema": {
      "type": "object",
      "properties": {
        "script": {
	  "type": "string",
	  "description": "Sed script to be executed."
	},
        "filespecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files to edit. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of sed command line arguments. Allowed are: --posix -s -E -r --regexp-extended --."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"util-sed-inline",
    "description": "Stream editor - inline replace allowed",
    "command": "util-sed.sh --posix -s -i -E -r --regexp-extended --",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "script": {
	  "type": "string",
	  "description": "Sed script to be executed."
	},
        "filespecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files to edit. Only paths relative to the current directory allowed."
        },
	"arguments": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of sed command line arguments. Allowed are: --posix -s -i -E -r --regexp-extended --."
	}
      },
      "required": ["filespecs"],
      "additionalProperties": false
    }
  },
  {
    "name":"util-uniq",
    "description": "Count newline, word and bytes for files",
    "command": "allowed-tool-one-file.sh uniq -c -d -D -i -u",
    "inputSchema": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Specific file to operate on. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of uniq command line arguments. Allowed are: -c -d -D -i -u."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"util-diff",
    "description": "Compare two files",
    "command": "allowed-tool.sh diff -c -d -D -i -u --",
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to compare. Only paths relative to the current directory allowed."
        },
	"arguments": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of diff command line arguments. Allowed are: -c -d -D -i -u --."
	}
      },
      "required": ["pathspecs"],
      "additionalProperties": false
    }
  },
  {
    "name":"util-patch",
    "description": "Count newline, word and bytes for files",
    "command": "util-patch.sh -b --backup-if-mismatch --no-backup-if-mismatch -c --dry-run -e -f -F -l -n --posix -s -t -T -u -Z",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Read the patch from path. Same as patch option -i. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "List of patch command line arguments. Allowed are: -b --backup-if-mismatch --no-backup-if-mismatch -c --dry-run -e -f -F <number> -l -n -p<number> --posix -s -t -T -u -Z."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  }
]
