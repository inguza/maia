{
  model: $model,
  store: false,
  max_completion_tokens: $max_tokens,
  n: 1,
  stream: false,
  messages: $messages[0]
}
+
(if $temperature != null then {temperature: $temperature} else {} end)
+
(if $top_p != null then {top_p: $top_p} else {} end)
+
(if $tools != null then {tools: $tools} else {} end)
