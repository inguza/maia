(
  .[]
  | select(.type == "text")
  | "[" + .filename + "]\n```\n" + .content + "```"
),
(
  [
    .[]
    | select(.type != "text")
    | "[" + .filename + "]\n"
      + "Binary " + (.type // "unknown")
      + " file of type '" + (.mime // "unknown") + "'."
  ] as $attachments
  | if ($attachments | length) > 0 then
      "\n\nIn addition there are attachments in the following order:\n\n"
      + ($attachments | join("\n\n"))
    else
      empty
    end
)
