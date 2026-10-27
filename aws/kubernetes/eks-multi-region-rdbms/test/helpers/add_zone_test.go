package helpers

import (
	"os/exec"
	"strings"
	"testing"
)

func TestAddZoneAbortsCallerWhenZoneListIsUnset(t *testing.T) {
	t.Parallel()

	// Given: a zone name exists, but the generated zone list is absent.
	cmd := exec.Command("bash", "-c", `
. ./lib-management-api.sh
unset CAMUNDA_MULTIREGION_ZONES
export CAMUNDA_ZONE_NAMES="london paris zurich"
jq() { return 0; }
camunda::add_zone cluster-london 2
printf 'CALLER-CONTINUED'
`)
	cmd.Dir = ProcedureDir(t)

	// When: the caller attempts to add the zone without errexit.
	out, err := cmd.CombinedOutput()

	// Then: the required-input guard aborts the caller itself.
	if err == nil || strings.Contains(string(out), "CALLER-CONTINUED") {
		t.Fatalf("expected missing zone list to abort the caller, got %v:\n%s", err, out)
	}
}
