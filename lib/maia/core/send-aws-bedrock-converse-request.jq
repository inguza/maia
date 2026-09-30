{
  system: [{text: $system}],
  messages: $messages,
  parameters: (
    {
      maxTokens: $maxTokensToSample,
      stopSequences: $stopSequences
    }
    +
    (if $temperature != null then {temperature: $temperature} else {} end)
  )
}
+
(if $tools != null then {toolConfig: {tools: $tools}} else {} end)
