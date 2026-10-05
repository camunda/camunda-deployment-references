package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// fakeRestoreAWS serves three global clusters: one whose writer is away from
// region 0, one already home, and one that does not match the filter.
const fakeRestoreAWS = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *describe-global-clusters*--global-cluster-identifier*)
    echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]}' ;;
  *describe-global-clusters*)
    echo '[
      {"GlobalClusterIdentifier":"e2e-fo-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]},
      {"GlobalClusterIdentifier":"e2e-fb-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:c","IsWriter":true}]},
      {"GlobalClusterIdentifier":"e2e-fo-999999-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:d","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:e","IsWriter":true}]}
    ]' ;;
  *describe-db-clusters*) echo 2000-01-01T00:00:00Z ;;
esac
`

func TestRestoreAuroraWritersMovesOnlyMatchingStrayWriters(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeRestoreAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "123456", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("restore failed: %v\n%s", err, out)
	}
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	switches := strings.Count(string(calls), "failover-global-cluster")
	if switches != 1 || !strings.Contains(string(calls),
		"failover-global-cluster --global-cluster-identifier e2e-fo-123456-global-db --target-db-cluster-identifier arn:aws:rds:eu-west-2:1:cluster:a") {
		t.Fatalf("want one switchover of e2e-fo-123456 to region 0, got %d\n%s\n%s", switches, calls, out)
	}
}
