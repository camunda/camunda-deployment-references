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
// fails FAKE_RETRIES times with the "replication setup" error, then moves the
// writer to eu-west-3.
const fakeSwitchAWS = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/args"
case "$*" in
  *failover-global-cluster*)
    n=$(grep -c failover-global-cluster "$FAKE_DIR/args")
    if [ "$n" -le "${FAKE_RETRIES:-0}" ]; then
      echo "The switchover request is not successful because replication setup is still in progress. Please retry the request later." >&2
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
		name, retries, already string
		wantSwitches           int
	}{
		{"moves the writer", "0", "", 1},
		{"retries while replication sets up", "2", "", 3},
		{"leaves a writer already in place", "0", "yes", 0},
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
				"FAKE_RETRIES="+tc.retries, "FAKE_ALREADY="+tc.already,
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
