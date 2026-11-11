{
  input: (.usage.input_tokens // .usage.inputTokens // 0),
  cached: (.usage.input_tokens_details.cached_tokens // .usage.cached_tokens // .usage.cacheReadInputTokens // 0),
  output: (.usage.output_tokens // .usage.outputTokens // 0),
  reasoning: (.usage.output_tokens_details.reasoning_tokens // .usage.reasoning_tokens // .usage.reasoningTokens // 0)
}
