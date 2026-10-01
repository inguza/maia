{
  model: $model,
  store: false,
  max_output_tokens: $max_tokens,
  stream: false,
  input: $messages[0]
}
+
(if $temperature != null then {temperature: $temperature} else {} end)
+
(if $top_p != null then {top_p: $top_p} else {} end)
+
(if $max_tool_calls != null then {max_tool_calls: $max_tool_calls} else {} end)
+
(if $tools != null then {tools: $tools} else {} end)
