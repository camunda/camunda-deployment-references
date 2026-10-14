package helpers

import (
	"os"
	"strconv"
	"testing"
)

// ClusterPrefix keeps the CI identity within infra's 14-character LB prefix
// and app's 17-character target-group prefix, including the three-character region.
// Local runs retain their existing suite names, random tags and overrides.
func ClusterPrefix(t *testing.T, suite string) string {
	t.Helper()
	id := os.Getenv("TEST_RUN_ID")
	if id == "" {
		if prefix := os.Getenv("TEST_CLUSTER_PREFIX"); prefix != "" {
			return prefix
		}
		return "e2e-" + suite + "-" + RunTag()
	}
	runID, err := strconv.ParseUint(id, 10, 64)
	if err != nil || runID == 0 {
		t.Fatalf("TEST_RUN_ID must be a positive decimal integer, got %q", id)
	}
	code, ok := map[string]string{
		"tgw-rdbms": "t", "os": "o", "byo": "b",
		"fo-planned": "p", "fo-unplanned": "u", "fb-noswitch": "n", "fb-switch": "s",
	}[suite]
	if !ok {
		t.Fatalf("unknown ECS test suite %q", suite)
	}
	prefix := "e2e-" + code + "-" + strconv.FormatUint(runID, 36)
	if len(prefix) > 14 {
		t.Fatalf("CI cluster prefix %q exceeds the 14-character naming limit", prefix)
	}
	return prefix
}
