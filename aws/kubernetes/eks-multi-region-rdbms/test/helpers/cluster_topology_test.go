package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestClusterTopologyChecksOnlyActiveZones(t *testing.T) {
	t.Parallel()

	// Given: two complete zones and a spare slot that is not part of the cluster.
	dir := t.TempDir()
	script, err := os.ReadFile(filepath.Join(ProcedureDir(t), "check-cluster-topology.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "check-cluster-topology.sh"), script, 0600); err != nil {
		t.Fatal(err)
	}
	const gateway = `camunda::gateway_get() {
printf '%s' '{"brokers":[{"brokerId":"london_0","partitions":[]},{"brokerId":"paris_0","partitions":[]}],"partitionsCount":3,"replicationFactor":2}'
}`
	if err := os.WriteFile(filepath.Join(dir, "lib-management-api.sh"), []byte(gateway), 0600); err != nil {
		t.Fatal(err)
	}
	// Run from the repository, not the temporary directory: asdf shims such as
	// jq resolve their version from the working directory's .tool-versions, and
	// a CI runner has no global one. The output file still goes to dir.
	cmd := exec.Command("bash", filepath.Join(dir, "check-cluster-topology.sh"))
	cmd.Dir = ProcedureDir(t)
	cmd.Env = (Env{RegionSlots: 3, ActiveRegions: 2, BrokersPerRegion: 1,
		ZoneReplicas: []int{1, 1, 1}, ZoneNames: []string{"london", "paris", "zurich"},
		ClusterContexts: []string{"cluster-london", "cluster-paris"},
		Namespace:       "camunda", ReleaseName: "camunda",
		// The stub answers at once, so a script that keeps polling has failed.
		// Without this a missing tool such as jq turns into a 25-minute wait.
		Extra: map[string]string{
			"TOPOLOGY_TIMEOUT_SECONDS": "0",
			"OUTPUT_FILE":              filepath.Join(dir, "zeebe-topology.json"),
		}}).Vars()

	// When: the procedure checks the real topology response shape.
	out, err := cmd.CombinedOutput()

	// Then: the complete active cluster passes without reporting a spare zone.
	if err != nil || strings.Contains(string(out), "zurich:") {
		t.Fatalf("expected only active zones to be checked, got %v:\n%s", err, out)
	}
}
