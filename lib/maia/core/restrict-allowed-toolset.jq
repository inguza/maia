# Materialize an allowlist after subtracting restriction rules. Keep the
# effect-matching semantics aligned with generate-allowed-toolset.jq.
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

def allowed_effects($modifiers; $defaults):
  reduce $modifiers[] as $modifier (
    $defaults;
    if ($modifier | startswith("-")) then
      . - [($modifier | ltrimstr("-"))]
    else
      . + [$modifier]
    end
  ) | unique;

def rule_matches($name; $tool_effects; $rule; $defaults):
  ($rule | split_pattern) as $parsed |
  ($name | test($parsed.pattern | glob_to_regex))
  and
  (($tool_effects - allowed_effects($parsed.effects; $defaults)) | length) == 0;

def restriction_matches($name; $tool_effects; $restriction; $defaults):
  ($restriction | split_pattern) as $parsed |
  ($name | test($parsed.pattern | glob_to_regex))
  and
  (
    # A restriction without an effect suffix removes every matching
    # allowance for the tool. A suffixed restriction removes only the
    # allowance space that covers this tool's effects.
    ($restriction | contains(":")) | not
    or
    (($tool_effects - allowed_effects($parsed.effects; $defaults)) | length) == 0
  );

# First apply the same allow-rule matching and duplicate-name resolution as
# generate-allowed-toolset.jq. Then subtract restrictions from that effective
# tool set and materialize the smallest explicit rule for each remaining tool.
[
  .[] |
  select(
    .name as $name |
    (.effects // []) as $tool_effects |
    any($patterns[];
      . as $rule |
      rule_matches($name; $tool_effects; $rule; $default_allowed_effects)
    )
  )
]
| reduce .[] as $tool ({}; .[$tool.name] = $tool)
| [.[] |
    . as $tool |
    ($tool.name) as $name |
    ($tool.effects // []) as $tool_effects |
    select(
      (any($restrictions[]?;
        restriction_matches($name; $tool_effects; .; $default_allowed_effects)
      )) | not
    ) |
    ($tool_effects - $default_allowed_effects | unique) as $needed_effects |
    if ($needed_effects | length) == 0 then
      $tool.name
    else
      $tool.name + ":" + ($needed_effects | join("+"))
    end
  ]
| unique
| sort
| .[]
