package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseAuroraWriterRegion(t *testing.T) {
	t.Parallel()

	const (
		london = "arn:aws:rds:eu-west-2:1:cluster:london"
		paris  = "arn:aws:rds:eu-west-3:1:cluster:paris"
	)
	region, err := ParseAuroraWriterRegion([]byte(`{"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":false},{"DBClusterArn":"` + paris + `","IsWriter":true}]}`))
	if err != nil || region != "eu-west-3" {
		t.Errorf("settled: got %q, %v", region, err)
	}

	// #3572: the old writer is still reported while the switchover runs.
	if _, err := ParseAuroraWriterRegion([]byte(`{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":true}]}`)); err == nil {
		t.Error("accepted a writer while the switchover was in progress")
	}

	// AWS names the field IsWriter; IsClusterWriter does not exist.
	if _, err := ParseAuroraWriterRegion([]byte(`{"GlobalClusterMembers":[{"DBClusterArn":"` + paris + `","IsClusterWriter":true}]}`)); err == nil {
		t.Error("accepted IsClusterWriter as the writer flag")
	}
}

// fakeAWS replays #3572: after failover-global-cluster, describe-global-clusters
// reports the old writer with a FailoverState for two polls, then the new
// writer while FailoverState is still set, and only then the settled cluster.
const fakeAWS = `#!/usr/bin/env bash
calls="$FAKE_DIR/calls"
n=$(( $(cat "$calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$calls"
echo "$*" >> "$FAKE_DIR/args"
if [ "$n" -le 2 ]; then
  echo '{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true}]}'
elif [ "$n" -eq 3 ]; then
  echo '{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}'
else
  echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}'
fi
`

func TestAuroraWaitWriterWaitsForTheGlobalCluster(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./aurora.sh
aurora_wait_writer arn:aws:rds:eu-west-3:1:cluster:b 60
cat "$FAKE_DIR/calls"`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(out)), "4") {
		t.Fatalf("returned before the switchover finished: %v\n%s", err, out)
	} // The CLI default region can be the lost one: ask the target's region.
	if args, _ := os.ReadFile(filepath.Join(fake, "args")); !strings.Contains(string(args), "--region eu-west-3") {
		t.Errorf("describe-global-clusters did not target the new writer's region:\n%s", args)
	}
}

// Every procedure that moves the Aurora writer goes through aurora_switch_to,
// which settles, skips a writer already in place, and waits for the global
// cluster (#3572). Both references carry the same aurora.sh.
func TestWriterMovesGoThroughAuroraSwitchTo(t *testing.T) {
	t.Parallel()

	ecs := filepath.Join("..", "..", "..", "procedure")
	eks := filepath.Join("..", "..", "..", "..", "..", "kubernetes", "eks-multi-region-rdbms", "procedure")
	for _, dir := range []string{ecs, eks} {
		for _, script := range []string{"failover.sh", "failback.sh"} {
			body, err := os.ReadFile(filepath.Join(dir, script))
			if err != nil {
				t.Fatal(err)
			}
			src := string(body)
			if strings.Contains(src, "rds failover-global-cluster") {
				t.Errorf("%s/%s calls failover-global-cluster itself instead of aurora_switch_to", dir, script)
			}
			if !strings.Contains(src, "aurora_switch_to") {
				t.Errorf("%s/%s does not move the writer with aurora_switch_to", dir, script)
			}
		}
	}
	ecsCopy, err := os.ReadFile(filepath.Join(ecs, "aurora.sh"))
	if err != nil {
		t.Fatal(err)
	}
	eksCopy, err := os.ReadFile(filepath.Join(eks, "aurora.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if string(ecsCopy) != string(eksCopy) {
		t.Error("the ECS and EKS copies of procedure/aurora.sh differ; keep them identical")
	}
}

// fakeSwitchAWS starts with the writer in eu-west-2. failover-global-cluster
// fails FAKE_RETRIES times with FAKE_REJECT (default: the "replication setup"
// error), then moves the writer to eu-west-3.
const fakeSwitchAWS = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/args"
case "$*" in
  *failover-global-cluster*)
    n=$(grep -c failover-global-cluster "$FAKE_DIR/args")
    if [ "$n" -le "${FAKE_RETRIES:-0}" ]; then
      echo "${FAKE_REJECT:-The switchover request is not successful because replication setup is still in progress. Please retry the request later.}" >&2
      exit 254
    fi
    touch "$FAKE_DIR/switched" ;;
  *describe-global-clusters*)
    if [ -f "$FAKE_DIR/switched" ] || [ -n "${FAKE_ALREADY:-}" ]; then
      echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}'
    else
      echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]}'
    fi ;;
esac
`

func TestAuroraSwitchTo(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name, retries, already, reject string
		wantSwitches                   int
	}{
		{"moves the writer", "0", "", "", 1},
		{"retries while replication sets up", "2", "", "", 3},
		// Seen about 1s after a cancelled switchover.
		{"retries while the target is modifying", "1", "", "An error occurred (InvalidDBClusterStateFault) when calling the FailoverGlobalCluster operation: The global cluster can't switch over because the target DB cluster is in the modifying state.", 2},
		{"leaves a writer already in place", "0", "yes", "", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			fake := t.TempDir()
			if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeSwitchAWS), 0o755); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./aurora.sh
aurora_switch_to arn:aws:rds:eu-west-3:1:cluster:b 60`)
			cmd.Dir = filepath.Join("..", "..", "..", "procedure")
			cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
				"FAKE_RETRIES="+tc.retries, "FAKE_ALREADY="+tc.already, "FAKE_REJECT="+tc.reject,
				"AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
			out, err := cmd.CombinedOutput()
			args, _ := os.ReadFile(filepath.Join(fake, "args"))
			if err != nil || strings.Count(string(args), "failover-global-cluster") != tc.wantSwitches {
				t.Fatalf("want %d switchover calls and success, got %v\n%s\n%s", tc.wantSwitches, err, args, out)
			}
			// The CLI default region can be the lost one: every call names the target's region.
			for _, line := range strings.Split(strings.TrimSpace(string(args)), "\n") {
				if !strings.Contains(line, "--region eu-west-3") {
					t.Errorf("call without the target region: %s", line)
				}
			}
		})
	}
}

// Settling can use the whole budget. A switchover started then could not be
// awaited and would keep running after the error, so none may start.
func TestAuroraSwitchToStartsNothingWithoutBudget(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeSwitchAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./aurora.sh
aurora_switch_to arn:aws:rds:eu-west-3:1:cluster:b 0`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	args, _ := os.ReadFile(filepath.Join(fake, "args"))
	if err == nil || !strings.Contains(string(out), "no time left") || strings.Contains(string(args), "failover-global-cluster") {
		t.Fatalf("want an error and no switchover, got %v\n%s\n%s", err, args, out)
	}
}

// A retryable error can sleep past the deadline. The next attempt would
// start a switchover that nothing waits for, so none may follow.
func TestAuroraSwitchToRetriesNothingPastTheDeadline(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeSwitchAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `. ./aurora.sh; aurora_switch_to arn:aws:rds:eu-west-3:1:cluster:b 3`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"FAKE_RETRIES=99", "AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=4")
	out, err := cmd.CombinedOutput()
	args, _ := os.ReadFile(filepath.Join(fake, "args"))
	if err == nil || strings.Count(string(args), "failover-global-cluster") != 1 || !strings.Contains(string(out), "none was started") {
		t.Fatalf("want one attempt and a budget error, got %v\n%s\n%s", err, args, out)
	}
}

func TestAuroraSwitchToFailsOnOtherErrors(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	aws := "#!/usr/bin/env bash\ncase \"$*\" in\n  *failover-global-cluster*) echo 'InvalidDBClusterStateFault: primary unavailable' >&2; exit 254 ;;\n  *) echo '{\"GlobalClusterMembers\":[{\"DBClusterArn\":\"arn:aws:rds:eu-west-2:1:cluster:a\",\"IsWriter\":true}]}' ;;\nesac\n"
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(aws), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `. ./aurora.sh; aurora_switch_to arn:aws:rds:eu-west-3:1:cluster:b 60`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "primary unavailable") {
		t.Fatalf("want the AWS error and a failure, got %v\n%s", err, out)
	}
}

func TestAuroraWaitWriterFailsOnTimeout(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./aurora.sh
aurora_wait_writer arn:aws:rds:eu-west-3:1:cluster:b 0`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "did not finish within 0s") {
		t.Fatalf("expected a timeout, got %v\n%s", err, out)
	}
}

func TestParseAuroraWriterRegionAcceptsEmptyFailoverState(t *testing.T) {
	t.Parallel()
	// Given: AWS reports an empty operation object and a settled writer.
	raw := []byte(`{"FailoverState":{},"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}`)
	// When
	region, err := ParseAuroraWriterRegion(raw)
	// Then
	if err != nil || region != "eu-west-3" {
		t.Fatalf("empty failover state rejected: %q, %v", region, err)
	}
}

func TestAuroraWaitWriterRejectsEmptyTarget(t *testing.T) {
	t.Parallel()
	// Given: no writer exists and the caller has no target ARN.
	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte("#!/usr/bin/env bash\necho '{\"GlobalClusterMembers\":[]}'\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./aurora.sh
aurora_wait_writer "" 5`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
	// When
	out, err := cmd.CombinedOutput()
	// Then
	if err == nil || !strings.Contains(string(out), "no target writer ARN") {
		t.Fatalf("expected an empty-target error, got %v\n%s", err, out)
	}
}

func TestScaleDownRegionHonoursOptionalProfile(t *testing.T) {
	for _, profile := range []string{"", "sandbox"} {
		t.Run("profile="+profile, func(t *testing.T) {
			// Given: a fake CLI rejects empty profile arguments.
			fake := t.TempDir()
			if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(`#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_DIR/args"
while [ "$#" -gt 0 ]; do
  if [ "$1" = --profile ] && [ -z "$2" ]; then exit 1; fi
  shift
done
`), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", fake+":"+os.Getenv("PATH"))
			t.Setenv("FAKE_DIR", fake)
			// When
			ScaleDownRegion(t, profile, "eu-west-2", "cluster")
			// Then
			args, err := os.ReadFile(filepath.Join(fake, "args"))
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(string(args), "--profile") != (profile != "") {
				t.Fatalf("unexpected profile arguments: %s", args)
			}
		})
	}
}

// A rerun can find the previous switchover early, while the failed region
// still has IsWriter set. Deciding from that state starts a second switchover,
// which AWS rejects. The helper must return only the settled membership.
func TestAuroraSettledGlobalWaitsForTheSwitchover(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./aurora.sh
aurora_settled_global eu-west-3 60 | jq -r '.GlobalClusterMembers[] | select(.IsWriter) | .DBClusterArn'`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.Output()
	if err != nil || strings.TrimSpace(string(out)) != "arn:aws:rds:eu-west-3:1:cluster:b" {
		t.Fatalf("want the settled writer on stdout, got %v\n%s", err, out)
	}
}

// fakeStuckAWS keeps the writer in eu-west-2. Once failover-global-cluster
// ran, the switchover stays "switching-over" (FAKE_STUCK) or is gone without a
// move, as when a second call targeting the current writer cancels it.
const fakeStuckAWS = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/args"
case "$*" in
  *failover-global-cluster*) touch "$FAKE_DIR/started" ;;
  *)
    if [ -f "$FAKE_DIR/started" ] && [ -n "${FAKE_STUCK:-}" ]; then
      echo '{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]}'
    else
      echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]}'
    fi ;;
esac
`

func runStuckSwitch(t *testing.T, script string, env ...string) (string, int, string) {
	t.Helper()
	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeStuckAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", "set -euo pipefail\n. ./aurora.sh\n"+script)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"AURORA_GLOBAL_CLUSTER_ID=g"), env...)
	out, _ := cmd.CombinedOutput()
	args, _ := os.ReadFile(filepath.Join(fake, "args"))
	return string(out), cmd.ProcessState.ExitCode(), string(args)
}

// #3676: a switchover that ended with the writer elsewhere cannot finish
// later, so the wait fails on the first settled read, not after the timeout.
// It returns 2: a rerun settles and switches again, nothing needs unplanned
// recovery.
func TestAuroraWaitWriterFailsWhenTheSwitchoverEndedElsewhere(t *testing.T) {
	t.Parallel()
	out, code, args := runStuckSwitch(t, "aurora_wait_writer arn:aws:rds:eu-west-3:1:cluster:b 60",
		"AURORA_WRITER_POLL_SECONDS=0")
	if code != 2 || !strings.Contains(out, "ended without moving the writer") || strings.Count(args, "describe-global-clusters") != 1 {
		t.Fatalf("want an immediate failure, got exit %d\n%s\n%s", code, args, out)
	}
}

// #3677: out of budget while its own switchover still runs, the helper
// returns 2 and says to rerun, so callers do not send the operator to the
// unplanned (data-losing) recovery.
func TestAuroraSwitchToReportsARunningSwitchover(t *testing.T) {
	t.Parallel()
	out, code, args := runStuckSwitch(t, "aurora_switch_to arn:aws:rds:eu-west-3:1:cluster:b 2",
		"AURORA_WRITER_POLL_SECONDS=1", "FAKE_STUCK=yes")
	if code != 2 || !strings.Contains(out, "still switching-over") || !strings.Contains(out, "rerun") ||
		strings.Count(args, "failover-global-cluster") != 1 {
		t.Fatalf("want exit 2 and a rerun hint, got exit %d\n%s\n%s", code, args, out)
	}
}

// #3677: settling a switchover that outlives the budget is the same case.
func TestAuroraSettledGlobalReportsARunningSwitchover(t *testing.T) {
	t.Parallel()
	out, code, _ := runStuckSwitch(t, "touch \"$FAKE_DIR/started\"; aurora_settled_global eu-west-3 0",
		"AURORA_WRITER_POLL_SECONDS=0", "FAKE_STUCK=yes")
	if code != 2 || !strings.Contains(out, "rerun") {
		t.Fatalf("want exit 2 and a rerun hint, got exit %d\n%s", code, out)
	}
}

// #3678: a failed AWS read is not an empty global cluster. failback.sh must
// show the AWS error instead of "not found or has no members".
func TestFailbackReportsAWSReadErrors(t *testing.T) {
	t.Parallel()
	fake := t.TempDir()
	body, err := os.ReadFile(filepath.Join("..", "..", "..", "procedure", "failback.sh"))
	if err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{
		"failback.sh": string(body),
		"zeebe_management_api.sh": `mgmt_log() { echo "$*"; }
mgmt_err() { echo "$*" >&2; }
mgmt_topology_summary() { :; }
`,
		"aurora.sh": "",
		"aws":       "#!/usr/bin/env bash\necho 'An error occurred (ExpiredTokenException): token expired' >&2\nexit 254\n",
	} {
		if err := os.WriteFile(filepath.Join(fake, name), []byte(content), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command("bash", filepath.Join(fake, "failback.sh"), "--failed-region", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"),
		"REGION_0=eu-west-2", "REGION_1=eu-west-3", "CLUSTER_0=c0-cluster", "CLUSTER_1=c1-cluster",
		"AURORA_GLOBAL_CLUSTER_ID=g", "ALB_ENDPOINT_0=a0", "ALB_ENDPOINT_1=a1", "ADMIN_USER=u", "ADMIN_PASS=p")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "ExpiredTokenException") || strings.Contains(string(out), "no members") {
		t.Fatalf("want the AWS error, got %v\n%s", err, out)
	}
}

// #3677: failover.sh must not send the operator to the data-losing unplanned
// recovery when aurora_switch_to returns 2 (a rerun finishes the move).
func TestFailoverHintFollowsTheSwitchResult(t *testing.T) {
	t.Parallel()
	body, err := os.ReadFile(filepath.Join("..", "..", "..", "procedure", "failover.sh"))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		rc         string
		wantUnplan bool
	}{{"2", false}, {"1", true}} {
		t.Run("rc="+tc.rc, func(t *testing.T) {
			t.Parallel()
			// Given: the zone is already gone and the writer is in the failed region.
			fake := t.TempDir()
			for name, content := range map[string]string{
				"failover.sh": string(body),
				"zeebe_management_api.sh": `mgmt_log() { echo "$*"; }
mgmt_err() { echo "$*" >&2; }
mgmt_topology_summary() { :; }
mgmt_tunnel_open() { :; }
mgmt_tunnel_close() { :; }
mgmt_zone_present() { return 1; }
`,
				"aurora.sh": `aurora_settled_global() { echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]}'; }
aurora_switch_to() { return "$FAKE_RC"; }
`,
				"aws":  "#!/usr/bin/env bash\necho available\n",
				"curl": "#!/usr/bin/env bash\n",
			} {
				if err := os.WriteFile(filepath.Join(fake, name), []byte(content), 0o755); err != nil {
					t.Fatal(err)
				}
			}
			cmd := exec.Command("bash", filepath.Join(fake, "failover.sh"), "--failed-region", "0", "--keep-tasks")
			cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_RC="+tc.rc,
				"REGION_0=eu-west-2", "REGION_1=eu-west-3", "CLUSTER_0=c0-cluster", "CLUSTER_1=c1-cluster",
				"AURORA_GLOBAL_CLUSTER_ID=g", "ALB_ENDPOINT_0=a0", "ALB_ENDPOINT_1=a1", "ADMIN_USER=u", "ADMIN_PASS=p")
			// When
			out, err := cmd.CombinedOutput()
			// Then
			if err == nil || !strings.Contains(string(out), "did not complete") ||
				strings.Contains(string(out), "unplanned recovery procedure") != tc.wantUnplan {
				t.Fatalf("want failure with unplanned hint=%v, got %v\n%s", tc.wantUnplan, err, out)
			}
		})
	}
}
