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
. ./zeebe_management_api.sh
aurora_wait_writer arn:aws:rds:eu-west-3:1:cluster:b 60
cat "$FAKE_DIR/calls"`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(out)), "4") {
		t.Fatalf("returned before the switchover finished: %v\n%s", err, out)
	}
}

// Every procedure that moves the Aurora writer must wait for the global
// cluster, not for the target cluster alone or a fixed sleep (#3572).
func TestWriterMovesWaitForTheGlobalCluster(t *testing.T) {
	t.Parallel()

	for _, script := range []string{"failover.sh", "failback.sh"} {
		body, err := os.ReadFile(filepath.Join("..", "..", "..", "procedure", script))
		if err != nil {
			t.Fatal(err)
		}
		src := string(body)
		if strings.Contains(src, "failover-global-cluster") && !strings.Contains(src, "aurora_wait_writer") {
			t.Errorf("%s moves the writer without aurora_wait_writer", script)
		}
	}
}

func TestAuroraWaitWriterFailsOnTimeout(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./zeebe_management_api.sh
aurora_wait_writer arn:aws:rds:eu-west-3:1:cluster:b 0`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "Timed out") {
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
. ./zeebe_management_api.sh
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
