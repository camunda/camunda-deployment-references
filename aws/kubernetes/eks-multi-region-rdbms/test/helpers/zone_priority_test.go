package helpers

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenerateZeebeHelmValuesRejectsNonPositiveZonePriority(t *testing.T) {
	t.Parallel()

	env := Env{
		RegionSlots:        3,
		ActiveRegions:      3,
		BrokersPerRegion:   2,
		ClusterContexts:    []string{"cluster-london", "cluster-paris", "cluster-zurich"},
		SubmarinerClusters: []string{"london", "paris", "zurich"},
		ZoneNames:          []string{"london", "paris", "zurich"},
		Namespace:          "camunda",
		ReleaseName:        "camunda",
		Extra: map[string]string{
			"CAMUNDA_ZONE_PRIORITY_BASE": "100",
			"CAMUNDA_ZONE_PRIORITY_STEP": "50",
		},
	}

	dir := ProcedureDir(t)
	cmd := exec.Command("bash", filepath.Join(dir, "generate-zeebe-helm-values.sh"))
	cmd.Dir = dir
	cmd.Env = env.Vars()

	output, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("expected a non-positive zone priority to be rejected, got success:\n%s", output)
	}
	if !strings.Contains(string(output), "zone slot 2 has priority 0") {
		t.Fatalf("expected the failing zone and priority in the error, got:\n%s", output)
	}
}
