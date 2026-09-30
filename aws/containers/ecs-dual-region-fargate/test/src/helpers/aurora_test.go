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

// fakeAWS replays #3572: describe-global-clusters keeps reporting the old
// writer and a FailoverState for two polls after failover-global-cluster.
const fakeAWS = `#!/usr/bin/env bash
calls="$FAKE_DIR/calls"
n=$(( $(cat "$calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$calls"
if [ "$n" -le 2 ]; then
  echo '{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true}]}'
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
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(out)), "3") {
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
