# What the runs admitted within PROVISION_MINUTES still have to create, for
# resource $k in region $r, given the current usage $used. Input: the pending
# runs; $aged: the live runs past that window.
#
# A run that recorded its admission usage (`base`) is credited with what
# appeared since the earliest such admission: those resources are already in
# $used and must not count twice. What the aged runs may have created in that
# time is not credited, so their resources never cancel a younger run's
# reservation. Deletions lower the credit too. Both err on the safe side.
# Runs without `base` keep their full needs.
def need: select(.regions | index($r)) | .needs[$k] // 0;
[.[] | select((need) > 0)] as $runs
| ($runs | map(select(.base[$r][$k] != null))) as $based
| ($runs | map(select(.base[$r][$k] == null)) | map(need) | add // 0) as $unbased
| ($aged | map(need) | add // 0) as $older
| if ($based | length) == 0 then $unbased
  else
    ([0, $used - ($based | map(.base[$r][$k]) | min) - $older] | max) as $appeared
    | ([0, ($based | map(need) | add) - $appeared] | max) + $unbased
  end
