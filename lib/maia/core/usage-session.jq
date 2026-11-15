include "usage-totals";

if $mode == "last" then
    (.[-1] // null) as $last
    | if $json then
        {last: $last, max_input_tokens: $max_input_tokens}
      elif $last == null then
        "No usage has been recorded for this session."
      else
        "\(report("Last usage at \($last.timestamp)"; $last))\n  API type: \($last.api_type)\n  Model: \($last.model)\n  Configured max input tokens: \($max_input_tokens)"
      end
elif $mode == "summary" then
    totals(.) as $session
    | totals([.[] | select((.timestamp // "")[0:8] == $today)]) as $day
    | if $json then
        {session: $session, today: $day, last: (.[-1] // null), max_input_tokens: $max_input_tokens}
      else
        "\(report("Usage this session"; $session))\n\n\(report("Usage today (\($today_label))"; $day))"
      end
else
    totals([.[] | select((.timestamp // "") >= $start and (.timestamp // "") <= $end)]) as $total
    | if $json then
        {range: {start: $start, end: $end}, usage: $total}
      else
        report($label; $total)
      end
end
