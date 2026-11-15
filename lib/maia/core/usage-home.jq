include "usage-totals";

if $mode == "summary" then
    totals(.) as $home
    | totals([.[] | select((.timestamp // "")[0:8] == $today)]) as $day
    | if $json then
        {home: $home, today: $day}
      else
        "\(report("Usage across this MAIA home"; $home))\n\n\(report("Usage today (\($today_label))"; $day))"
      end
else
    totals([.[] | select((.timestamp // "") >= $start and (.timestamp // "") <= $end)]) as $total
    | if $json then
        {range: {start: $start, end: $end}, usage: $total}
      else
        report($label; $total)
      end
end
