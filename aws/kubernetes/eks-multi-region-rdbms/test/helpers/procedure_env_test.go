package helpers

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

// The Helm chart pin has two readers: the procedure a user sources and this
// test harness. They have to resolve to the same commit, or CI validates a
// chart nobody deploys.
func TestChartGitRefComesFromTheProcedure(t *testing.T) {
	t.Setenv("CAMUNDA_HELM_CHART_GIT_REF", "")

	dir := ProcedureDir(t)
	cmd := exec.Command("bash", "-c",
		`grep -o 'CAMUNDA_HELM_CHART_GIT_REF:-[^}]*' export_environment_prerequisites.sh | head -1 | cut -d- -f2-`)
	cmd.Dir = dir

	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("cannot read the pin from the procedure: %v", err)
	}

	want := strings.TrimSpace(string(out))
	if want == "" {
		t.Fatal("no CAMUNDA_HELM_CHART_GIT_REF default found in the procedure")
	}
	if got := ChartGitRef(); got != want {
		t.Fatalf("chart pin drifted: harness has %q, procedure has %q", got, want)
	}
}

func TestChartGitRefHonoursAnExplicitOverride(t *testing.T) {
	t.Setenv("CAMUNDA_HELM_CHART_GIT_REF", "my-branch")

	if got := ChartGitRef(); got != "my-branch" {
		t.Fatalf("expected the override to win, got %q", got)
	}
}

// A variable already exported by the developer's shell must not survive into a
// procedure the harness configures, or the test asserts against an environment
// it does not control.
func TestVarsOverrideTheAmbientEnvironment(t *testing.T) {
	t.Setenv("CAMUNDA_ACTIVE_REGIONS", "99")

	vars := Env{RegionSlots: 3, ActiveRegions: 2, BrokersPerRegion: 2}.Vars()

	seen := 0
	for _, entry := range vars {
		if strings.HasPrefix(entry, "CAMUNDA_ACTIVE_REGIONS=") {
			seen++
			if entry != "CAMUNDA_ACTIVE_REGIONS=2" {
				t.Fatalf("expected the harness value, got %q", entry)
			}
		}
	}
	if seen != 1 {
		t.Fatalf("expected exactly one CAMUNDA_ACTIVE_REGIONS entry, got %d", seen)
	}
}

// INC-5340: the procedures must refuse to authenticate rather than fall back to
// the chart's demo admin login.
func TestBasicAuthRefusesToInventCredentials(t *testing.T) {
	t.Parallel()

	dir := ProcedureDir(t)
	cmd := exec.Command("bash", "-c",
		`set -euo pipefail
source ./lib-management-api.sh
camunda::_basic_auth`)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "CAMUNDA_BASIC_AUTH_USER=", "CAMUNDA_BASIC_AUTH_PASSWORD=")

	output, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("expected a failure without credentials, got %q", output)
	}
	if !strings.Contains(string(output), "CAMUNDA_BASIC_AUTH_USER must be set") {
		t.Fatalf("expected the guard message, got %q", output)
	}
	if strings.Contains(string(output), "demo") {
		t.Fatalf("the credential fallback is back: %q", output)
	}
}

func TestBasicAuthEmitsTheConfiguredPair(t *testing.T) {
	t.Parallel()

	dir := ProcedureDir(t)
	cmd := exec.Command("bash", "-c",
		`set -euo pipefail
source ./lib-management-api.sh
camunda::_basic_auth`)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(),
		"CAMUNDA_BASIC_AUTH_USER=alice", "CAMUNDA_BASIC_AUTH_PASSWORD=s3cret")

	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("emitting the credential pair failed: %v\n%s", err, output)
	}
	if got := strings.TrimSpace(string(output)); got != "alice:s3cret" {
		t.Fatalf("expected alice:s3cret, got %q", got)
	}
}

// A bootstrap prepares every active region; a single-region activation or
// failback must not reach into the clusters that are still serving traffic.
func TestTargetSlotsDefaultsToEveryActiveRegion(t *testing.T) {
	t.Parallel()

	if got := runTargetSlots(t, ""); got != "0\n1\n2" {
		t.Fatalf("expected every active slot, got %q", got)
	}
}

func TestTargetSlotsNarrowsToTheGivenSlot(t *testing.T) {
	t.Parallel()

	if got := runTargetSlots(t, "1"); got != "1" {
		t.Fatalf("expected only slot 1, got %q", got)
	}
}

func TestTargetSlotsRejectsAnUndeployedSlot(t *testing.T) {
	t.Parallel()

	dir := ProcedureDir(t)
	cmd := exec.Command("bash", "-c",
		`source ./lib-management-api.sh
camunda::target_slots 9`)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "CAMUNDA_ACTIVE_REGIONS=3")

	output, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("expected slot 9 to be rejected, got %q", output)
	}
	if !strings.Contains(string(output), "is not a deployed slot") {
		t.Fatalf("expected the slot guard message, got %q", output)
	}
}

func runTargetSlots(t *testing.T, slot string) string {
	t.Helper()

	dir := ProcedureDir(t)
	cmd := exec.Command("bash", "-c",
		`source ./lib-management-api.sh
camunda::target_slots "$1"`, "bash", slot)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "CAMUNDA_ACTIVE_REGIONS=3")

	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("camunda::target_slots failed: %v\n%s", err, output)
	}
	return strings.TrimSpace(string(output))
}
