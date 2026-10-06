package helpers

import (
	"os/exec"
	"testing"
)

func TestZoneReplicaValidationWhenReplicationFactorIsOverridden(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name, layout string
		accepted     bool
	}{
		{"valid", "2 1 1", true},
		{"zero in spare slot", "2 1 0", false},
		{"non-numeric in spare slot", "2 1 invalid", false},
		{"too many in spare slot", "2 1 3", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Given: an explicit RF must not bypass validation of spare slots.
			env := Env{RegionSlots: 3, ActiveRegions: 2, BrokersPerRegion: 2,
				AWSRegions:         []string{"a", "b", "c"},
				ClusterContexts:    []string{"a", "b", "c"},
				SubmarinerClusters: []string{"a", "b", "c"},
				Extra: map[string]string{"CAMUNDA_ZONE_REPLICAS": tc.layout,
					"CAMUNDA_REPLICATION_FACTOR": "17"}}
			cmd := exec.Command("bash", "-c", `
set -euo pipefail
. ./export_environment_prerequisites.sh >/dev/null
printf '%s' "$CAMUNDA_REPLICATION_FACTOR"
`)
			cmd.Dir = ProcedureDir(t)
			cmd.Env = env.Vars()

			// When: the environment validates the layout and derives RF.
			out, err := cmd.CombinedOutput()

			// Then: invalid layouts fail and a valid layout preserves the override.
			if (err == nil) != tc.accepted || (tc.accepted && string(out) != "17") {
				t.Fatalf("accepted=%v: got %v:\n%s", tc.accepted, err, out)
			}
		})
	}
}
