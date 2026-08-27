[
  {
    "name":"util-grep",
    "description": "Search files using regular expression.",
    "command": "grep.sh -R -E -F -G -i -v -w -x -c -s -n -a -I --",
    "parameters": {
      "type": "object",
      "properties": {
        "searchpattern": {
          "type": "string",
          "description": "Regular expression to search for."
        },
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to search in. Only paths relative to the current directory allowed. Multiple files can be separated by space. If absent data is read from stdin."
        },
	"after-context": {
	  "type": "string",
	  "description": "Print before-context lines of trailing context after matching lines."
	},
	"before-context": {
	  "type": "string",
	  "description": "Print before-context lines of leading context after matching lines."
	},
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of grep command line arguments. Allowed are: -R -E -F -G -i -v -w -x -c -s -n -a -I."
	}
      },
      "required": ["searchpattern"]
    },
    "strict": true
  },
  {
    "name":"util-find",
    "description": "Search files - but not files starting with a .",
    "command": "find.sh -d -depth -executable -nogroup -nouser -readable -ls",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to search for. Multiple files can be separated by space. Only paths relative to the current directory allowed."
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
          "description": "Space separated list of find command line arguments. Allowed are: -d -depth -executable -nogroup -nouser -readable -ls."
	}
      },
      "required": ["pathspec"]
    },
    "strict": true
  },
  {
    "name":"util-ls",
    "description": "List files",
    "command": "allowed-tool.sh ls -B -l --time-style=long-iso -d -f -G -h -o -t -r -U -1 --",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to list. Multiple files can be separated by space. Only paths relative to the current directory allowed."
        },
	"arguments": {
	  "type": "string",
	  "description": "Space separated list of ls command line arguments. Allowed are: -B -l --time-style=long-iso -d -f -G -h -o -t -r -U -1"
	}
      },
      "required": ["pathspec"]
    },
    "strict": true
  },
  {
    "name":"util-sort",
    "description": "List files",
    "command": "allowed-tool.sh sort -n -s -v --show-nonprinting --",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to sort. Only paths relative to the current directory allowed. Multiple files can be separated by space. If absent data is read from stdin."
        },
	"arguments": {
          "type": "string",
          "description": "Space separated list of sort command line arguments. Allowed are: -n -s -v --show-nonprinting."
	}
      },
      "required": []
    },
    "strict": true
  },
  {
    "name":"util-head",
    "description": "Output the first part of files",
    "command": "head-tail.sh head --",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to print the head for. Only paths relative to the current directory allowed. Multiple files can be separated by space. If absent data is read from stdin."
        },
	"lines": {
          "type": "string",
          "description": "Print the first <lines> lines instead of the first 10."
	}
      },
      "required": []
    },
    "strict": true
  },
  {
    "name":"util-tail",
    "description": "Output the last part of files",
    "command": "head-tail.sh tail --",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to print the tail of. Only paths relative to the current directory allowed. Multiple files can be separated by space. If absent data is read from stdin."
        },
	"lines": {
          "type": "string",
          "description": "Print the last <lines> lines instead of the last 10."
	}
      },
      "required": []
    },
    "strict": true
  },
  {
    "name":"util-wc",
    "description": "Count newline, word and bytes for files",
    "command": "allowed-tool.sh wc -c --bytes -m --chars -l --lines -w --words --",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to count in. Only paths relative to the current directory allowed. Multiple files can be separated by space. If absent data is read from standin."
        },
	"arguments": {
          "type": "string",
          "description": "Space separated list of wc command line arguments. Allowed are: -c --bytes -m --chars -l --lines -w --words."
	}
      },
      "required": []
    },
    "strict": true
  },
  {
    "name":"util-sed",
    "description": "Stream editor - write forbidden",
    "command": "sed.sh --posix -s -E -r --regexp-extended --",
    "parameters": {
      "type": "object",
      "properties": {
        "script": {
	  "type": "string",
	  "description": "Sed script to be executed."
	},
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to edit. Only paths relative to the current directory allowed. Multiple files can be separated by space. If absent data is read from stdin."
        },
	"arguments": {
          "type": "string",
          "description": "Space separated list of sed command line arguments. Allowed are: --posix -s -E -r --regexp-extended."
	}
      },
      "required": []
    },
    "strict": true
  },
  {
    "name":"write-util-sed",
    "description": "Stream editor - write allowed",
    "command": "sed.sh --posix -s -i -E -r --regexp-extended --",
    "parameters": {
      "type": "object",
      "properties": {
        "script": {
	  "type": "string",
	  "description": "Sed script to be executed."
	},
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to edit. Only paths relative to the current directory allowed. Multiple files can be separated by space. If absent data is read from stdin."
        },
	"arguments": {
          "type": "string",
          "description": "Space separated list of sed command line arguments. Allowed are: --posix -s -i -E -r --regexp-extended."
	}
      },
      "required": []
    },
    "strict": true
  },
  {
    "name":"util-uniq",
    "description": "Count newline, word and bytes for files",
    "command": "allowed-tool-one-file.sh uniq -c -d -D -i -u",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Specific file to operate on. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
          "type": "string",
          "description": "Space separated list of uniq command line arguments. Allowed are: -c -d -D -i -u."
	}
      },
      "required": []
    },
    "strict": true
  },
  {
    "name":"util-diff",
    "description": "Compare two files",
    "command": "allowed-tool.sh diff -c -d -D -i -u --",
    "parameters": {
      "type": "object",
      "properties": {
        "pathspec": {
          "type": "string",
          "description": "Pattern of files and directories to compare. Only paths relative to the current directory allowed. Multiple files can be separated by space."
        },
	"arguments": {
          "type": "string",
          "description": "Space separated list of uniq command line arguments. Allowed are: -c -d -D -i -u."
	}
      },
      "required": ["pathspec"]
    },
    "strict": true
  },
  {
    "name":"write-util-patch",
    "description": "Count newline, word and bytes for files",
    "command": "patch.sh -b --backup-if-mismatch --no-backup-if-mismatch -c --dry-run -e -f -F -l -n --posix -s -t -T -u -Z",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Read the patch from path. Same as patch option -i. Only paths relative to the current directory allowed. If absent data is read from stdin."
        },
	"arguments": {
          "type": "string",
          "description": "Space separated list of patch command line arguments. Allowed are: -b --backup-if-mismatch --no-backup-if-mismatch -c --dry-run -e -f -F <number> -l -n -p<number> --posix -s -t -T -u -Z"
	}
      },
      "required": []
    },
    "strict": true
  }
]
