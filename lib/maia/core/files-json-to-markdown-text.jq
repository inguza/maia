.[]
| select(.type == "text")
| "[" + .filename + "]\n```\n" + .content + "```"
