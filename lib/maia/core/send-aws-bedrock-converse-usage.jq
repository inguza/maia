{
  input: (.usage.inputTokens // 0),
  cached: (.usage.cacheReadInputTokens // 0),
  output: (.usage.outputTokens // 0),
  reasoning: (.usage.reasoningTokens // .usage.outputTokensDetails.reasoningTokens // 0)
}
