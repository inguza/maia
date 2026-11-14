{
  model: $model,
  input: $messages[0]
}
+
(if $tools != null then {tools: $tools} else {} end)
