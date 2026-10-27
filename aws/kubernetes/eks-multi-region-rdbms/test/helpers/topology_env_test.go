package helpers

import (
	"os/exec"
	"strings"
	"testing"
)

func TestOnlyActiveZonesAreDeclared(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name             string
		slots, active    int
		brokers          int
		layout           []int
		wantRF, wantSize string
		wantPartitions   string
	}{
		{"two active of three", 3, 2, 2, nil, "4", "4", "6"},
		{"all three active", 3, 3, 2, nil, "5", "6", "6"},
		{"two active of four", 4, 2, 2, nil, "4", "4", "8"},
		{"all four active", 4, 4, 2, nil, "6", "8", "8"},
		{"asymmetric spare", 4, 3, 3, []int{3, 1, 2, 3}, "6", "9", "12"},
		{"asymmetric complete", 4, 4, 3, []int{3, 1, 2, 3}, "9", "12", "12"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Given: the harness and the shell receive identical topology inputs.
			env := Env{RegionSlots: tc.slots, ActiveRegions: tc.active,
				BrokersPerRegion: tc.brokers, ZoneReplicas: tc.layout,
				AWSRegions:         []string{"a", "b", "c", "d"},
				ClusterContexts:    []string{"a", "b", "c", "d"},
				SubmarinerClusters: []string{"a", "b", "c", "d"}}
			vars := env.Vars()
			cmd := exec.Command("bash", "-c", `
set -euo pipefail
unset CAMUNDA_REPLICATION_FACTOR CAMUNDA_CLUSTER_SIZE CAMUNDA_PARTITION_COUNT
. ./export_environment_prerequisites.sh >/dev/null
printf '%s %s %s' "$CAMUNDA_REPLICATION_FACTOR" "$CAMUNDA_CLUSTER_SIZE" "$CAMUNDA_PARTITION_COUNT"
`)
			cmd.Dir = ProcedureDir(t)
			cmd.Env = vars

			// When: the procedure derives its values independently of the harness.
			out, err := cmd.CombinedOutput()

			// Then: both implementations match the expected active-zone topology.
			if err != nil {
				t.Fatalf("sourcing the procedure environment failed: %v\n%s", err, out)
			}
			want := strings.Join([]string{tc.wantRF, tc.wantSize, tc.wantPartitions}, " ")
			if string(out) != want {
				t.Fatalf("procedure: expected RF, size, partitions %q, got %q", want, out)
			}
			assertVar(t, vars, "CAMUNDA_REPLICATION_FACTOR", tc.wantRF)
			assertVar(t, vars, "CAMUNDA_CLUSTER_SIZE", tc.wantSize)
			assertVar(t, vars, "CAMUNDA_PARTITION_COUNT", tc.wantPartitions)
		})
	}
}
