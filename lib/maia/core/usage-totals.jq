def totals($events):
    reduce $events[] as $event (
        {input: 0, cached: 0, output: 0, reasoning: 0};
        .input += ($event.input // 0)
        | .cached += ($event.cached // 0)
        | .output += ($event.output // 0)
        | .reasoning += ($event.reasoning // 0)
    );
def report($title; $total):
    "\($title)\n  Input: \($total.input)\n  Cached: \($total.cached)\n  Output: \($total.output)\n  Reasoning: \($total.reasoning)";
