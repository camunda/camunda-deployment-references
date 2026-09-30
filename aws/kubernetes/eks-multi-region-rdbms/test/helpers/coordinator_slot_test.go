package helpers

import (
	"os/exec"
	"strings"
	"testing"
)

func TestEnvironmentRejectsSpareZoneAsConfigurationCoordinator(t *testing.T) {
	t.Parallel()

	output, err := sourceEnvironmentPrerequisites(t, []string{"london", "paris", "frankfurt"}, 2)

	if err == nil {
		t.Fatalf("expected spare zone frankfurt to be rejected, got success:\n%s", output)
	}
	if !strings.Contains(string(output), "frankfurt") {
		t.Fatalf("expected the offending zone in the error, got:\n%s", output)
	}
}

func TestEnvironmentAcceptsActiveZoneAsConfigurationCoordinator(t *testing.T) {
	t.Parallel()

	output, err := sourceEnvironmentPrerequisites(t, []string{"london", "paris", "zurich"}, 2)

	if err != nil {
		t.Fatalf("expected default growth layout to pass: %v\n%s", err, output)
	}
}

func sourceEnvironmentPrerequisites(t *testing.T, zones []string, activeRegions int) ([]byte, error) {
	t.Helper()

	dir := ProcedureDir(t)
	env := Env{
		RegionSlots:        len(zones),
		ActiveRegions:      activeRegions,
		BrokersPerRegion:   2,
		AWSRegions:         []string{"eu-west-2", "eu-west-3", "eu-central-1"},
		ClusterContexts:    []string{"cluster-london", "cluster-paris", "cluster-spare"},
		SubmarinerClusters: zones,
		ZoneNames:          zones,
	}
	cmd := exec.Command("bash", "-c", "source ./export_environment_prerequisites.sh")
	cmd.Dir = dir
	cmd.Env = env.Vars()

	return cmd.CombinedOutput()
}
