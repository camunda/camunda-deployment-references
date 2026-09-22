package helpers

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestUseSurvivingRegionReplacesLostAWSRegion(t *testing.T) {
	t.Parallel()

	dir := ProcedureDir(t)
	command := `source ./lib-management-api.sh
camunda::use_surviving_region 0
printf '%s' "$AWS_REGION"`
	cmd := exec.Command("bash", "-c", command)
	cmd.Dir = dir
	cmd.Env = append(Env{
		ActiveRegions:   3,
		AWSRegions:      []string{"eu-west-2", "eu-west-3", "eu-central-2"},
		ClusterContexts: []string{"cluster-london", "cluster-paris", "cluster-zurich"},
	}.Vars(), "AWS_REGION=eu-west-2")

	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("selecting a surviving AWS region failed: %v\n%s", err, output)
	}
	if got := strings.TrimSpace(string(output)); !strings.HasSuffix(got, "eu-west-3") {
		t.Fatalf("expected eu-west-3, got %q", got)
	}
}

func TestUseSurvivingRegionPreservesConfiguredSurvivor(t *testing.T) {
	t.Parallel()

	dir := ProcedureDir(t)
	command := `source ./lib-management-api.sh
camunda::use_surviving_region 0
printf '%s' "$AWS_REGION"`
	cmd := exec.Command("bash", "-c", command)
	cmd.Dir = filepath.Clean(dir)
	cmd.Env = append(Env{
		ActiveRegions:   3,
		AWSRegions:      []string{"eu-west-2", "eu-west-3", "eu-central-2"},
		ClusterContexts: []string{"cluster-london", "cluster-paris", "cluster-zurich"},
	}.Vars(), "AWS_REGION=eu-central-2")

	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("preserving a configured survivor failed: %v\n%s", err, output)
	}
	if got := strings.TrimSpace(string(output)); got != "eu-central-2" {
		t.Fatalf("expected eu-central-2, got %q", got)
	}
}
