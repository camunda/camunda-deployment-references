package helpers

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// runPartitioning sources the management-API library and pipes a cluster
// response through camunda::partitioning, so the procedures' own parsing is
// exercised rather than a Go reimplementation of it.
func runPartitioning(t *testing.T, clusterJSON string) (string, error) {
	t.Helper()

	lib := filepath.Join(ProcedureDir(t), "lib-management-api.sh")
	cmd := exec.Command("bash", "-c", `. "$1" && camunda::partitioning`, "bash", lib)
	cmd.Stdin = strings.NewReader(clusterJSON)

	out, err := cmd.CombinedOutput()
	return string(out), err
}

// The cluster API is renaming /cluster/partition-distribution to
// /cluster/partitioning. Both spellings have to resolve, because the
// procedures run against engines on either side of that rename.
func TestPartitioningReadsBothSpellings(t *testing.T) {
	t.Parallel()

	for name, cluster := range map[string]string{
		"legacy":  `{"partitionDistribution":{"zones":[{"name":"paris"},{"name":"london"}]}}`,
		"renamed": `{"partitioning":{"zones":[{"name":"paris"},{"name":"london"}]}}`,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			out, err := runPartitioning(t, cluster)
			if err != nil {
				t.Fatalf("expected the %s spelling to resolve, got %v:\n%s", name, err, out)
			}
			if !strings.Contains(out, `"paris"`) {
				t.Fatalf("expected the zone list in the output, got:\n%s", out)
			}
		})
	}
}

// The regression this guards: jq's `?` swallowed a missing field, so a response
// carrying the other spelling read as "no such zone" and sent failback.sh down
// its re-add branch for a zone that was never removed — on a live cluster,
// without erroring. Anything short of a usable zone list has to fail here
// instead of reaching that branch, including an empty list: a cluster always
// has at least one zone, so an empty one is an incomplete response rather than
// a membership state worth acting on.
func TestPartitioningRejectsUnusableResponses(t *testing.T) {
	t.Parallel()

	for name, cluster := range map[string]string{
		"neither spelling":     `{"brokers":[{"nodeId":0}]}`,
		"unnamed zone entries": `{"partitioning":{"zones":["paris"]}}`,
		"empty zone list":      `{"partitioning":{"zones":[]}}`,
		"blank zone name":      `{"partitioning":{"zones":[{"name":""}]}}`,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			out, err := runPartitioning(t, cluster)
			if err == nil {
				t.Fatalf("expected %s to be rejected, got success:\n%s", name, out)
			}
			if !strings.Contains(out, "no valid partition distribution") {
				t.Fatalf("expected the failure to name the missing partition distribution, got:\n%s", out)
			}
		})
	}
}
