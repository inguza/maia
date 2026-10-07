.[]
| "[" + .filename + "]\n"
  + (if .type == "text" then
       "```\n" + .content + "```"
     else
       "Binary " + (.type // "unknown") + " file of type '" + (.mime // "unknown") + "'."
     end)

