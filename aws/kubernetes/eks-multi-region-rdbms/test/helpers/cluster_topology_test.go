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
	cmd := exec.Command("bash", "check-cluster-topology.sh")
	cmd.Dir = dir
	cmd.Env = (Env{RegionSlots: 3, ActiveRegions: 2, BrokersPerRegion: 1,
		ZoneReplicas: []int{1, 1, 1}, ZoneNames: []string{"london", "paris", "zurich"},
		ClusterContexts: []string{"cluster-london", "cluster-paris"},
		Namespace:       "camunda", ReleaseName: "camunda"}).Vars()

	// When: the procedure checks the real topology response shape.
	out, err := cmd.CombinedOutput()

	// Then: the complete active cluster passes without reporting a spare zone.
	if err != nil || strings.Contains(string(out), "zurich:") {
		t.Fatalf("expected only active zones to be checked, got %v:\n%s", err, out)
	}
}
