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

def has_available_tool_dependencies($available):
  . as $tool |
  all(($tool["tool-dependencies"] // [])[];
    . as $dependency | ($available | index($dependency)) != null
  );

def available_tool_names($tools):
  ([$tools[] | select(."exec-dependencies-missing" == null) | .name] | unique) as $initial |
  $initial
  | until(
      . as $available |
      ([$tools[]
        | select(.name as $name | ($available | index($name)) != null)
        | select(has_available_tool_dependencies($available))
        | .name
      ] | unique) == $available;
      . as $available |
      [$tools[]
        | select(.name as $name | ($available | index($name)) != null)
        | select(has_available_tool_dependencies($available))
        | .name
      ] | unique
    );

(
  [
    .[] |
    select(allowed_filter) as $item |
    [ $item["exec-dependencies"][]?
      | select(. as $dependency | ($missing_exec_dependencies | index($dependency)) != null)
    ]
    | unique as $missing
    | ($item | del(."exec-dependencies")) as $definition
    | if ($missing | length) > 0 then
        $definition + {"exec-dependencies-missing": $missing}
      else
        $definition
      end
  ]
  | reduce .[] as $item ({}; .[$item.name] = $item)
  | [.[]]
) as $tools
| available_tool_names($tools) as $available
| [
    $tools[] |
    . as $item |
    [ $item["tool-dependencies"][]?
      | select(. as $dependency | ($available | index($dependency)) == null)
    ]
    | unique as $missing
    | ($item | del(."tool-dependencies")) as $definition
    | if ($missing | length) > 0 then
        $definition + {"tool-dependencies-missing": $missing}
      else
        $definition
      end
  ]