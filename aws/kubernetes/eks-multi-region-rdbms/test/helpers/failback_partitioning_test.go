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

// The procedures track the current cluster API, which serves the partition
// distribution under `partitioning`.
func TestPartitioningReadsTheClusterResponse(t *testing.T) {
	t.Parallel()

	out, err := runPartitioning(t, `{"partitioning":{"zones":[{"name":"paris"},{"name":"london"}]}}`)
	if err != nil {
		t.Fatalf("expected the cluster response to resolve, got %v:\n%s", err, out)
	}
	if !strings.Contains(out, `"paris"`) {
		t.Fatalf("expected the zone list in the output, got:\n%s", out)
	}
}

// The regression this guards: jq's `?` swallowed a missing field, so a response
// the script could not read looked like "no such zone" and sent failback.sh down
// its re-add branch for a zone that was never removed — on a live cluster,
// without erroring. Anything short of a usable zone list has to fail here
// instead of reaching that branch. That includes a response from before the
// `/cluster/partition-distribution` rename: refusing loudly is recoverable,
// silently re-adding a live zone is not. An empty list counts too, since a
// cluster always has at least one zone, and a blank name can never match a
// recovered zone, which `camunda::zone_name` guarantees is non-empty.
func TestPartitioningRejectsUnusableResponses(t *testing.T) {
	t.Parallel()

	for name, cluster := range map[string]string{
		"pre-rename spelling":  `{"partitionDistribution":{"zones":[{"name":"paris"}]}}`,
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
