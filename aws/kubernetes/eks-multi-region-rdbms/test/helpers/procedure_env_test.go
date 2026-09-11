package helpers

import (
	"fmt"
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
	// Matched on the `${VAR:-default}` structure rather than by splitting on a
	// character: the default is a commit SHA today, but a tag such as
	// camunda-platform-8.10-15.0.0-alpha3 contains the separators a naive cut
	// would break on, and this check has to survive that.
	cmd := exec.Command("bash", "-c",
		`sed -n 's/^export CAMUNDA_HELM_CHART_GIT_REF="\${CAMUNDA_HELM_CHART_GIT_REF:-\(.*\)}"$/\1/p' export_environment_prerequisites.sh | head -1`)
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

// The zone layout has two readers: the procedure a user sources, and this
// harness. A copy is acceptable only while something fails when they diverge.
func TestZoneReplicasDefaultMatchesTheProcedure(t *testing.T) {
	for _, slots := range []int{2, 3, 4} {
		want := runProcedureZoneReplicas(t, slots)
		got := DefaultZoneReplicas(slots)

		if len(got) != len(want) {
			t.Fatalf("%d slots: harness returned %v, procedure returned %v", slots, got, want)
		}
		for i := range got {
			if fmt.Sprint(got[i]) != want[i] {
				t.Fatalf("%d slots: harness returned %v, procedure returned %v", slots, got, want)
			}
		}
	}
}

func TestZoneReplicasDefaultsToTwoTwoOne(t *testing.T) {
	t.Parallel()

	vars := Env{RegionSlots: 3, ActiveRegions: 3, BrokersPerRegion: 2}.Vars()

	assertVar(t, vars, "CAMUNDA_ZONE_REPLICAS", "2 2 1")
	assertVar(t, vars, "CAMUNDA_REPLICATION_FACTOR", "5")
}

// An explicit layout has to win, and the replication factor has to follow it
// rather than be restated: the two disagreeing is the failure this replaced.
func TestZoneReplicasHonoursAnExplicitLayout(t *testing.T) {
	t.Parallel()

	vars := Env{RegionSlots: 3, ActiveRegions: 3, BrokersPerRegion: 3, ZoneReplicas: []int{3, 3, 3}}.Vars()

	assertVar(t, vars, "CAMUNDA_ZONE_REPLICAS", "3 3 3")
	assertVar(t, vars, "CAMUNDA_REPLICATION_FACTOR", "9")
}

func assertVar(t *testing.T, vars []string, key, want string) {
	t.Helper()

	for _, entry := range vars {
		if k, v, found := strings.Cut(entry, "="); found && k == key {
			if v != want {
				t.Fatalf("%s: expected %q, got %q", key, want, v)
			}
			return
		}
	}
	t.Fatalf("%s not present in the rendered environment", key)
}

func runProcedureZoneReplicas(t *testing.T, slots int) []string {
	t.Helper()

	dir := ProcedureDir(t)
	cmd := exec.Command("bash", "-c", `
set -euo pipefail
export CAMUNDA_REGION_SLOTS="$1" CAMUNDA_ACTIVE_REGIONS="$1" CAMUNDA_BROKERS_PER_REGION=2
export AWS_REGIONS="a b c d" CLUSTER_CONTEXTS="a b c d" SUBMARINER_CLUSTER_IDS="a b c d"
export CAMUNDA_ZONE_NAMES="a b c d"
. ./export_environment_prerequisites.sh >/dev/null
printf '%s' "$CAMUNDA_ZONE_REPLICAS"
`, "bash", fmt.Sprint(slots))
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "CAMUNDA_ZONE_REPLICAS=", "CAMUNDA_REPLICATION_FACTOR=")

	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("reading the procedure default for %d slots failed: %v\n%s", slots, err, out)
	}
	return strings.Fields(string(out))
}
