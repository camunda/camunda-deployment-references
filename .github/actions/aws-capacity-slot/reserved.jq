# What the runs admitted within PROVISION_MINUTES still have to create, for
# resource $k in region $r, given the current usage $used.
#
# A run that recorded its admission usage (`base`) is credited with what
# appeared since the earliest such admission: those resources are already in
# $used and must not count twice. Deletions since then lower the credit, which
# errs on the safe side. Runs without `base` keep their full needs.
[.[] | select(.regions | index($r)) | select((.needs[$k] // 0) > 0)] as $runs
| ($runs | map(select(.base[$r][$k] != null))) as $based
| ($runs | map(select(.base[$r][$k] == null)) | map(.needs[$k]) | add // 0) as $unbased
| if ($based | length) == 0 then $unbased
  else
    ([0, $used - ($based | map(.base[$r][$k]) | min)] | max) as $appeared
    | ([0, ($based | map(.needs[$k]) | add) - $appeared] | max) + $unbased
  end
