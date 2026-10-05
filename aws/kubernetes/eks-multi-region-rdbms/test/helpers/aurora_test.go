package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const (
	london = "arn:aws:rds:eu-west-2:1:cluster:london"
	paris  = "arn:aws:rds:eu-west-3:1:cluster:paris"
)

func TestParseAuroraGlobal(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name, raw, writer, failover string
	}{
		{"settled", `{"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":false},{"DBClusterArn":"` + paris + `","IsWriter":true}]}`, "eu-west-3", ""},
		{"switching", `{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":true}]}`, "eu-west-2", "switching-over"},
	}
	for _, c := range cases {
		got, err := ParseAuroraGlobal([]byte(c.raw))
		if err != nil || got.WriterRegion != c.writer || got.FailoverState != c.failover {
			t.Errorf("%s: got %+v, %v", c.name, got, err)
		}
	}

	// The AWS field is IsWriter; IsClusterWriter does not exist and must not
	// silently count as a writer.
	if _, err := ParseAuroraGlobal([]byte(`{"GlobalClusterMembers":[{"DBClusterArn":"` + paris + `","IsClusterWriter":true}]}`)); err == nil {
		t.Error("IsClusterWriter was accepted as the writer flag")
	}
}

// fakeAWS replays #3572: after failover-global-cluster, describe-global-clusters
// reports the old writer with a FailoverState for two polls, then the new
// writer while FailoverState is still set, and only then the settled cluster.
const fakeAWS = `#!/usr/bin/env bash
calls="$FAKE_DIR/calls"
case "$*" in
  *describe-global-clusters*)
    n=$(( $(cat "$calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$calls"
    if [ "$n" -le 2 ]; then
      echo '{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":true},{"DBClusterArn":"` + paris + `","IsWriter":false}]}'
    elif [ "$n" -eq 3 ]; then
      echo '{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":false},{"DBClusterArn":"` + paris + `","IsWriter":true}]}'
    else
      echo '{"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":false},{"DBClusterArn":"` + paris + `","IsWriter":true}]}'
    fi ;;
esac
`

func runWaitAuroraWriter(t *testing.T, timeout string) (string, error) {
	t.Helper()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `set -euo pipefail
source ./lib-management-api.sh
camunda::wait_aurora_writer global "$TARGET" "$TIMEOUT"
cat "$FAKE_DIR/calls"`)
	cmd.Dir = ProcedureDir(t)
	cmd.Env = append(os.Environ(),
		"PATH="+fake+":"+os.Getenv("PATH"),
		"FAKE_DIR="+fake,
		"TARGET="+paris,
		"TIMEOUT="+timeout,
		"AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func TestWaitAuroraWriterReturnsOnlyOnceSwitchoverFinished(t *testing.T) {
	t.Parallel()

	out, err := runWaitAuroraWriter(t, "60")
	if err != nil {
		t.Fatalf("wait failed: %v\n%s", err, out)
	}
	// The fake settles on its 4th describe call. Fewer calls means the wait
	// returned while the switchover was still running.
	if !strings.HasSuffix(strings.TrimSpace(out), "\n4") {
		t.Fatalf("returned while the switchover was running\n%s", out)
	}
}

func TestWaitAuroraWriterFailsOnTimeout(t *testing.T) {
	t.Parallel()

	out, err := runWaitAuroraWriter(t, "0")
	if err == nil || !strings.Contains(out, "did not finish within 0s") {
		t.Fatalf("expected a timeout error, got %v\n%s", err, out)
	}
}

// Every procedure that moves the Aurora writer must wait for the global
// cluster, not for the target cluster alone (#3572).
func TestWriterMovesWaitForTheGlobalCluster(t *testing.T) {
	t.Parallel()

	for _, script := range []string{"failover.sh", "failback.sh"} {
		body, err := os.ReadFile(filepath.Join(ProcedureDir(t), script))
		if err != nil {
			t.Fatal(err)
		}
		src := string(body)
		if strings.Contains(src, "failover-global-cluster") && !strings.Contains(src, "camunda::wait_aurora_writer") {
			t.Errorf("%s moves the writer without camunda::wait_aurora_writer", script)
		}
		if strings.Contains(src, "wait db-cluster-available") {
			t.Errorf("%s waits on db-cluster-available, which returns before the switchover ends", script)
		}
	}
}

func TestWaitAuroraWriterRejectsEmptyTarget(t *testing.T) {
	t.Parallel()
	// Given: no writer exists and the caller has no target ARN.
	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte("#!/usr/bin/env bash\necho '{\"GlobalClusterMembers\":[]}'\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `set -euo pipefail
source ./lib-management-api.sh
camunda::wait_aurora_writer global "" 5`)
	cmd.Dir = ProcedureDir(t)
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "AURORA_WRITER_POLL_SECONDS=0")
	// When
	out, err := cmd.CombinedOutput()
	// Then
	if err == nil || !strings.Contains(string(out), "no target writer ARN") {
		t.Fatalf("expected an empty-target error, got %v\n%s", err, out)
	}
}

func TestFailoverRejectsMissingWriter(t *testing.T) {
	t.Parallel()
	// Given: an empty global membership and an offline management API.
	fake := t.TempDir()
	body, err := os.ReadFile(filepath.Join(ProcedureDir(t), "failover.sh"))
	if err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{
		"failover.sh": string(body),
		"lib-management-api.sh": `camunda::require_slot() { :; }
camunda::survivor_context() { echo survivor; }
camunda::use_surviving_region() { :; }
camunda::management() { echo '{}'; }
camunda::wait_aurora_writer() { :; }
`,
		"aws": "#!/usr/bin/env bash\necho '[]'\n",
	} {
		if err := os.WriteFile(filepath.Join(fake, name), []byte(content), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command("bash", filepath.Join(fake, "failover.sh"), "0", "--dry-run")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"),
		"CLUSTER_CONTEXTS=a b c", "AWS_REGIONS=eu-west-2 eu-west-3 eu-central-1",
		"CAMUNDA_ACTIVE_REGIONS=3", "CAMUNDA_REGION_SLOTS=3", "CAMUNDA_BROKERS_PER_REGION=2",
		"CAMUNDA_ZONE_REPLICAS=2 2 1", "CAMUNDA_REPLICATION_FACTOR=5", "AURORA_GLOBAL_CLUSTER_ID=g")
	// When
	out, err := cmd.CombinedOutput()
	// Then
	if err == nil || !strings.Contains(string(out), "No Aurora writer ARN") {
		t.Fatalf("expected a missing-writer error, got %v\n%s", err, out)
	}
}
