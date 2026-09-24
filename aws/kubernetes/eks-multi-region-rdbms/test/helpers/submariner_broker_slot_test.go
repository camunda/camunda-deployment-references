package helpers

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestDeployBrokerRejectsInvalidBrokerSlot(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		slot string
	}{
		{name: "non-numeric", slot: "oops"},
		{name: "negative", slot: "-1"},
		{name: "out of range", slot: "2"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			dir := ProcedureDir(t)
			cmd := exec.Command("bash", filepath.Join(dir, "submariner/deploy-broker.sh"))
			cmd.Dir = dir
			cmd.Env = append(Env{
				ActiveRegions:      2,
				ClusterContexts:    []string{"cluster-london", "cluster-paris"},
				SubmarinerClusters: []string{"london", "paris"},
			}.Vars(), "SUBMARINER_BROKER_SLOT="+test.slot)

			output, err := cmd.CombinedOutput()
			if err == nil {
				t.Fatalf("expected slot %q to be rejected, got success:\n%s", test.slot, output)
			}
			if !strings.Contains(string(output), "SUBMARINER_BROKER_SLOT") {
				t.Fatalf("expected a slot validation error, got:\n%s", output)
			}
		})
	}
}
