[
  {
    "name":"git-status",
    "description": "Git status.",
    "command": "git-pathspecs-common.sh status -s --short -b --branch",
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to check the status for. Only paths relative to the current directory allowed. If absent the status of the current directory is shown."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -s --short -b --branch."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-log",
    "description": "Git log.",
    "command": "git-pathspecs-common.sh log --no-decorate --source",
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to check the status for. Only paths relative to the current directory allowed. If absent current directory is logged."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: --no-decorate --source."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-show",
    "description": "Git show.",
    "command": "git-show.sh --abbrev-commit --oneline",
    "inputSchema": {
      "type": "object",
      "properties": {
        "objects": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Objects to show. If absent the last commit is shown."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: --abbrev-commit --oneline."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-diff",
    "description": "Git diff.",
    "command": "git-tree-pathspecs-common.sh diff switch -s --no-patch --raw --minimal --name-only --name-status --no-color -R --quiet --no-prefix --cached --merge-base",
    "inputSchema": {
      "type": "object",
      "properties": {
        "tree-ish": {
          "type": "string",
          "description": "The commit to diff against. The syntax <commit>...<commit> is also possible."
        },
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to diff. Only paths relative to the current directory allowed."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -s --no-patch --raw --minimal --name-only --name-status --no-color -R --quiet --no-prefix --cached --merge-base."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-commit",
    "description": "Git commit.",
    "command": "git-commit.sh --dry-run --short -q --quiet",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "message": {
	  "type": "string",
	  "description": "The commit message."
	},
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to commit. Only paths relative to the current directory allowed. If absent previously added and removed files are considered."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: --dry-run --short -q --quiet."
	}
      },
      "required": ["message"],
      "additionalProperties": false
    }
  },
  {
    "name":"git-reset",
    "description": "Git reset.",
    "command": "git-tree-pathspecs-common.sh reset --soft --mixed --hard --merge -q --quiet --no-refresh",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "tree-ish": {
	  "type": "string",
	  "description": "The Git tree-ish to reset to, such as a commit, branch, or tag. Defaults to HEAD."
	},
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to reset. Only paths relative to the current directory allowed."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: --soft --mixed --hard --merge -q --quiet --no-refresh."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-restore",
    "description": "Git restore.",
    "command": "git-pathspecs-common.sh restore -m --merge",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to restore. Only paths relative to the current directory allowed."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -m --merge."
	}
      },
      "required": ["pathspecs"],
      "additionalProperties": false
    }
  },
  {
    "name":"git-add",
    "description": "Git add.",
    "command": "git-pathspecs-common.sh add -f --force --dry-run -N --intent-to-add --refresh",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to add. Only paths relative to the current directory allowed."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -f --force --dry-run -N --intent-to-add --refresh."
	}
      },
      "required": ["pathspecs"],
      "additionalProperties": false
    }
  },
  {
    "name":"git-clean",
    "description": "Git clean.",
    "command": "git-pathspecs-common.sh clean -f --force -n --dry-run -q --quiet -x -X -d",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to remove. Only paths relative to the current directory allowed."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -f --force -n --dry-run -q --quiet -x -X -d."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-switch",
    "description": "Git switch.",
    "command": "git-switch.sh -c -C -f --force -q --quiet",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "branch": {
          "type": "string",
          "description": "The branch to switch to, or the new branch name if -c or -C is used."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -c -C -f --force -q --quiet."
	}
      },
      "required": ["branch"],
      "additionalProperties": false
    }
  },
  {
    "name":"git-rebase",
    "description": "Git rebase.",
    "command": "git-tree-ish-common.sh rebase --continue --skip --abort --quit -q --quiet -f --force-rebase --no-ff",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "tree-ish": {
          "type": "string",
          "description": "The upstream branch to rebase to."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: --continue --skip --abort --quit -q --quiet -f --force-rebase --no-ff."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-merge",
    "description": "Git merge.",
    "command": "git-tree-ish-common.sh merge --continue --abort --quit --apply -q --quiet --commit --no-commit -ff --ff-only --no-ff --squash --no-squash --stat -n --no-stat",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "tree-ish": {
          "type": "string",
          "description": "The upstream branch to merge into the current branch."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: --continue --abort --quit --apply --commit --no-commit -q --quiet -ff --ff-only --no-ff --squash --no-squash --stat -n --no-stat."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-revert",
    "description": "Git revert.",
    "command": "git-revert.sh -n --no-commit --continue --skip --quit --abort",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "commits": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of commits to revert."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -n --no-commit --continue --skip --quit --abort."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-branch",
    "description": "Git branch.",
    "command": "git-branch.sh -d -D -c -C -m -M",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "branch": {
          "type": "string",
          "description": "The branch name. The new branch name if -c, -C, -m or -M is specified."
        },
        "oldbranch": {
          "type": "string",
          "description": "The old branch name."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -d -D -c -C -m -M."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-rm",
    "description": "Git rm.",
    "command": "git-pathspecs-common.sh rm -f --force -n --dry-run -r --cached -q --quiet",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "pathspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Glob patterns of files and directories to remove. Only paths relative to the current directory allowed."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -f --force -n --dry-run -r --cached -q --quiet."
	}
      },
      "required": ["pathspecs"],
      "additionalProperties": false
    }
  },
  {
    "name":"git-mv",
    "description": "Git mv.",
    "command": "git-mv.sh -f --force -n --dry-run",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "source": {
          "type": "string",
          "description": "Source to rename."
        },
        "destination": {
          "type": "string",
          "description": "Destination, the new name."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -f --force -n --dry-run."
	}
      },
      "required": ["source","destination"],
      "additionalProperties": false
    }
  },
  {
    "name":"git-pull",
    "description": "Git pull.",
    "command": "git-refspec-common.sh pull -q --quiet --rebase --ff-only --ff --no-ff",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "repository": {
	  "type": "string",
	  "description": "The repository to pull."
	},
        "refspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
	  "description": "Git refspecs to pull."
        },    
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -q --quiet --rebase --ff-only --ff --no-ff."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-push",
    "description": "Git push.",
    "command": "git-refspec-common.sh push -q --quiet",
    "effects":["push"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "repository": {
	  "type": "string",
	  "description": "The repository to push to."
	},
        "refspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
	  "description": "Git refspecs to push."
        },    
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -q --quiet."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  },
  {
    "name":"git-fetch",
    "description": "Git fetch.",
    "command": "git-refspec-common.sh fetch -q --quiet -f --force -t --tags -n --no-tags --stdin",
    "effects":["write"],
    "inputSchema": {
      "type": "object",
      "properties": {
        "repository": {
	  "type": "string",
	  "description": "The repository to fetch."
	},
        "refspecs": {
          "type": "array",
          "items": {
            "type": "string"
          },
	  "description": "Git refspecs to fetch."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of git command line arguments. Allowed are: -q --quiet -f --force -t --tags -n --no-tags --stdin."
	}
      },
      "required": [],
      "additionalProperties": false
    }
  }
]
