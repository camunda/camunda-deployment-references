package helpers

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func runGenerateZeebeHelmValues(t *testing.T, releaseName string, zoneNames []string) (string, error) {
	t.Helper()

	env := Env{
		RegionSlots:        3,
		ActiveRegions:      2,
		BrokersPerRegion:   2,
		ClusterContexts:    []string{"cluster-london", "cluster-paris"},
		SubmarinerClusters: []string{"london", "paris", "zurich"},
		ZoneNames:          zoneNames,
		Namespace:          "camunda",
		ReleaseName:        releaseName,
	}

	dir := ProcedureDir(t)
	cmd := exec.Command("bash", filepath.Join(dir, "generate-zeebe-helm-values.sh"))
	cmd.Dir = dir
	cmd.Env = env.Vars()

	output, err := cmd.CombinedOutput()
	return string(output), err
}

// The chart names the headless Service of each zone <release>-zeebe-<zone>.
func TestGenerateZeebeHelmValuesUsesPerZoneServices(t *testing.T) {
	t.Parallel()

	output, err := runGenerateZeebeHelmValues(t, "camunda", []string{"london", "paris", "zurich"})
	if err != nil {
		t.Fatalf("generate-zeebe-helm-values.sh failed: %v\n%s", err, output)
	}

	want := "CAMUNDA_CLUSTER_INITIALCONTACTPOINTS=" +
		"london.camunda-zeebe-london.camunda.svc.clusterset.local.:26502," +
		"paris.camunda-zeebe-paris.camunda.svc.clusterset.local.:26502"
	if !strings.Contains(output, want) {
		t.Fatalf("expected %q in the output, got:\n%s", want, output)
	}
}

// Above 59 characters the chart replaces the name with a digest.
func TestGenerateZeebeHelmValuesServiceNameLengthBoundary(t *testing.T) {
	t.Parallel()

	// "-zeebe-london" is 13 characters.
	accepted := strings.Repeat("r", 59-13)
	if output, err := runGenerateZeebeHelmValues(t, accepted, []string{"london", "paris", "zurich"}); err != nil {
		t.Fatalf("expected a 59-character service name to be accepted: %v\n%s", err, output)
	}

	rejected := strings.Repeat("r", 60-13)
	output, err := runGenerateZeebeHelmValues(t, rejected, []string{"london", "paris", "zurich"})
	if err == nil {
		t.Fatalf("expected a 60-character service name to be rejected, got success:\n%s", output)
	}
	if !strings.Contains(output, "is longer than 59 characters") {
		t.Fatalf("expected the length error, got:\n%s", output)
	}
}

func TestGenerateZeebeHelmValuesRejectsShortZoneList(t *testing.T) {
	t.Parallel()

	output, err := runGenerateZeebeHelmValues(t, "camunda", []string{"london"})
	if err == nil {
		t.Fatalf("expected a short zone list to be rejected, got success:\n%s", output)
	}
	if !strings.Contains(output, "CAMUNDA_ZONE_NAMES has no entry for zone slot 1") {
		t.Fatalf("expected the missing-zone error, got:\n%s", output)
	}
}
