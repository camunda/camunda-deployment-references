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
// instead of reaching that branch. An empty list counts, since a cluster always
// has at least one zone, and so does a blank name, which can never match a
// recovered zone — `camunda::zone_name` guarantees that one is non-empty.
func TestPartitioningRejectsUnusableResponses(t *testing.T) {
	t.Parallel()

	for name, cluster := range map[string]string{
		"no partitioning field": `{"brokers":[{"nodeId":0}]}`,
		"unnamed zone entries":  `{"partitioning":{"zones":["paris"]}}`,
		"empty zone list":       `{"partitioning":{"zones":[]}}`,
		"blank zone name":       `{"partitioning":{"zones":[{"name":""}]}}`,
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

// failback.sh assigns the distribution to a variable under `set -euo pipefail`,
// and the whole guarantee rests on that assignment aborting the script: a
// rejected response has to stop the procedure outright, not leave the caller
// holding an empty value and fall through to the branch that POSTs a membership
// change. Calling the function directly, as the cases above do, cannot show it.
func TestPartitioningAbortsTheCallerOnAnUnusableResponse(t *testing.T) {
	t.Parallel()

	const script = `set -euo pipefail
. "$1"
partitioning="$(printf '%s' "$2" | camunda::partitioning)"
echo "REACHED-MEMBERSHIP-BRANCH with $partitioning"`

	const marker = "REACHED-MEMBERSHIP-BRANCH"

	for name, tc := range map[string]struct {
		cluster      string
		wantsToReach bool
	}{
		"usable response":    {`{"partitioning":{"zones":[{"name":"paris"}]}}`, true},
		"no partitioning":    {`{"brokers":[{"nodeId":0}]}`, false},
		"empty zone list":    {`{"partitioning":{"zones":[]}}`, false},
		"blank zone name":    {`{"partitioning":{"zones":[{"name":""}]}}`, false},
		"unnamed zone entry": {`{"partitioning":{"zones":["paris"]}}`, false},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			lib := filepath.Join(ProcedureDir(t), "lib-management-api.sh")
			out, err := exec.Command("bash", "-c", script, "bash", lib, tc.cluster).CombinedOutput()
			reached := strings.Contains(string(out), marker)

			switch {
			case tc.wantsToReach && err != nil:
				t.Fatalf("expected the caller to continue, got %v:\n%s", err, out)
			case tc.wantsToReach && !reached:
				t.Fatalf("expected the caller to reach the membership branch, got:\n%s", out)
			case !tc.wantsToReach && err == nil:
				t.Fatalf("expected the caller to abort, got success:\n%s", out)
			case !tc.wantsToReach && reached:
				t.Fatalf("expected the abort to precede the membership branch, got:\n%s", out)
			}
		})
	}
}
