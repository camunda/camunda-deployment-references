package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// runDetach runs test/detach-switched-aurora-members.sh against a stubbed AWS
// CLI holding one global cluster whose writer lives in writerRegion and was
// created ageHours ago. It returns the remove-from-global-cluster calls.
func runDetach(t *testing.T, match, minAge, writerRegion string, ageHours int) (removed []string, out string) {
	t.Helper()
	bin := t.TempDir()
	calls := filepath.Join(bin, "calls")
	created := time.Now().UTC().Add(-time.Duration(ageHours) * time.Hour).Format("2006-01-02T15:04:05.000000+00:00")

	arn := func(region, name string) string { return "arn:aws:rds:" + region + ":123456789012:cluster:" + name }
	members := map[string]string{
		"eu-west-2":    arn("eu-west-2", "eks-mr-abc-london-db"),
		"eu-west-3":    arn("eu-west-3", "eks-mr-abc-paris-db"),
		"eu-central-2": arn("eu-central-2", "eks-mr-abc-zurich-db"),
	}
	var json []string
	for region, a := range members {
		w := "false"
		if region == writerRegion {
			w = "true"
		}
		json = append(json, `{"DBClusterArn":"`+a+`","IsWriter":`+w+`}`)
	}
	globals := `[{"GlobalClusterIdentifier":"eks-mr-abc-global-db","GlobalClusterMembers":[` + strings.Join(json, ",") + `]}]`

	stub := `#!/bin/bash
echo "$*" >>"` + calls + `"
case "$2" in
describe-global-clusters) echo '` + globals + `' ;;
describe-db-clusters) echo '` + created + `' ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "aws"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command("bash", filepath.Join("..", "detach-switched-aurora-members.sh"), match, minAge)
	cmd.Env = append(os.Environ(), "PATH="+bin+":"+os.Getenv("PATH"), "TF_VAR_region_0=eu-west-2")
	o, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("the script must never fail the teardown, got %v:\n%s", err, o)
	}
	raw, _ := os.ReadFile(calls)
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.Contains(line, "remove-from-global-cluster") {
			removed = append(removed, line)
		}
	}
	return removed, string(o)
}

func TestDetachLeavesAWriterInRegionSlotZero(t *testing.T) {
	t.Parallel()

	// Given: no failover moved the writer, so terraform destroy works as is.
	// When: the teardown preparation runs.
	removed, out := runDetach(t, "^eks-mr-abc-", "0", "eu-west-2", 1)

	// Then: no member is detached.
	if len(removed) != 0 {
		t.Fatalf("expected no detach, got %v:\n%s", removed, out)
	}
}

func TestDetachRemovesReadersOfASwitchedWriter(t *testing.T) {
	t.Parallel()

	// Given: a failover left the writer in paris.
	// When: the teardown preparation runs.
	removed, out := runDetach(t, "^eks-mr-abc-", "0", "eu-west-3", 1)

	// Then: both readers are detached, each in its own region, and the writer is not.
	joined := strings.Join(removed, "\n")
	if len(removed) != 2 || strings.Contains(joined, "paris-db") ||
		!strings.Contains(joined, "--region eu-west-2") || !strings.Contains(joined, "--region eu-central-2") {
		t.Fatalf("expected the london and zurich readers detached in their regions, got %v:\n%s", removed, out)
	}
}

func TestDetachSkipsAClusterYoungerThanTheMinimumAge(t *testing.T) {
	t.Parallel()

	// Given: a switched writer created 3h ago, while the daily sweep only takes 12h and older.
	// When: the teardown preparation runs.
	removed, out := runDetach(t, "^eks-mr-", "12", "eu-west-3", 3)

	// Then: a test that may still be running is left alone.
	if len(removed) != 0 {
		t.Fatalf("expected the young cluster to be skipped, got %v:\n%s", removed, out)
	}
}

func TestDetachIgnoresOtherGlobalClusters(t *testing.T) {
	t.Parallel()

	// Given: a switched writer that belongs to another run.
	// When: the teardown preparation runs for a different cluster name.
	removed, out := runDetach(t, "^eks-mr-other-", "0", "eu-west-3", 1)

	// Then: nothing is detached.
	if len(removed) != 0 {
		t.Fatalf("expected no detach outside the regex, got %v:\n%s", removed, out)
	}
}
