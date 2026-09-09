def glob_to_regex:
  "^" +
  (gsub("\\."; "\\.")
  | gsub("\\*"; ".*")
  | gsub("\\?"; ".")) +
  "$";

def split_pattern:
  split(":") |
  {
    pattern: .[0],
    effects: (.[1] // "" |
      if . == "" then [] else split("+") end)
  };
    
def allowed_effects($modifiers):
  reduce $modifiers[] as $modifier (
    $default_allowed_effects;
    if ($modifier | startswith("-")) then
      . - [($modifier | ltrimstr("-"))]
    else
      . + [$modifier]
    end
  ) | unique;

def allowed_filter:
  .name as $name |
  (.effects // []) as $tool_effects |
    any($patterns[];
    . as $rule |
    ($rule | split_pattern) as $parsed |
    ($name | test($parsed.pattern | glob_to_regex))
    and
    (
      $tool_effects -
      (allowed_effects($parsed.effects))
      | length
    ) == 0
  );

[
  .[] |
  select(allowed_filter)
]
|
reduce .[] as $item (
  {};
  .[$item.name] = $item
)
| [.[]]
