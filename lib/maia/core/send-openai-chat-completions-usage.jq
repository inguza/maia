{
  input: (.usage.prompt_tokens // .usage.input_tokens // 0),
  cached: (.usage.prompt_tokens_details.cached_tokens // .usage.input_tokens_details.cached_tokens // 0),
  output: (.usage.completion_tokens // .usage.output_tokens // 0),
  reasoning: (.usage.completion_tokens_details.reasoning_tokens // .usage.output_tokens_details.reasoning_tokens // 0)
}
