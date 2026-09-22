package multiregionrdbmstests

import (
	"os"
	"testing"
	"time"

	"multiregionrdbmstests/helpers"
)

// TestCrossRegionConnectivity probes pod-to-pod reachability between every
// pair of active regions, without deploying Camunda.
//
// It is OPT-IN: it creates and deletes workloads in the Camunda namespace, so
// it is not something to run by accident against a cluster someone is using.
// Enable it with:
//
//	MULTIREGION_CONNECTIVITY_PROBE=true go test -run TestCrossRegionConnectivity
//
// Why it is worth running before TestMultiRegionDeployCamunda when changing
// anything about the network substrate: a broken substrate surfaces there as
// brokers stuck at 0/1 and HTTP 401 from the gateway, thirty minutes in and
// several layers away from the cause. This answers the same question in about
// two minutes, and distinguishes a discovery failure from a routing one.
func TestCrossRegionConnectivity(t *testing.T) {
	if os.Getenv("MULTIREGION_CONNECTIVITY_PROBE") != "true" {
		t.Skip("opt-in: set MULTIREGION_CONNECTIVITY_PROBE=true to run the cross-region probe")
	}

	env := testEnv(t)
	helpers.RunProcedure(t, env, 10*time.Minute, "verify-cross-region-connectivity.sh")
}
