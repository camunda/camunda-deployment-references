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
// without erroring.
func TestPartitioningRejectsAResponseCarryingNeitherSpelling(t *testing.T) {
	t.Parallel()

	out, err := runPartitioning(t, `{"brokers":[{"nodeId":0}]}`)
	if err == nil {
		t.Fatalf("expected a response without a partition distribution to be rejected, got success:\n%s", out)
	}
	if !strings.Contains(out, "no valid partition distribution") {
		t.Fatalf("expected the failure to name the missing partition distribution, got:\n%s", out)
	}
}

// A zones array whose entries are not named objects is malformed rather than
// empty: reporting it as "zone absent" would again pick the re-add branch.
func TestPartitioningRejectsMalformedZoneEntries(t *testing.T) {
	t.Parallel()

	out, err := runPartitioning(t, `{"partitioning":{"zones":["paris"]}}`)
	if err == nil {
		t.Fatalf("expected malformed zone entries to be rejected, got success:\n%s", out)
	}
	if !strings.Contains(out, "no valid partition distribution") {
		t.Fatalf("expected the failure to name the missing partition distribution, got:\n%s", out)
	}
}
