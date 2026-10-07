// Failback end-to-end tests.
//
// Sequence: deploy -> failover -> failback, asserting that region 0 returns to
// service and that the Aurora writer settles where each --switch-writer variant
// says it should.
//
// failover.sh promotes the surviving Aurora member itself, so by the time
// failback runs the writer is already in region 1 — this test asserts that
// precondition rather than creating it. What the two variants distinguish is
// whether failback moves it home.
//
// Replication factor is the load-bearing assertion on the Zeebe side; see
// doc.go. It runs 4 -> 2 -> 4, and only reaches 4 again if failback genuinely
// re-added the zone: restarted brokers rejoin membership but host no
// partitions until it is back, so a broker count cannot tell those apart.

package src

import (
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"

	"github.com/camunda/camunda-deployment-references/aws/containers/ecs-dual-region-fargate/test/src/helpers"
)

// TestFailback_NoSwitchWriter restores region 0's compute but leaves the
// database writer in region 1.
func TestFailback_NoSwitchWriter(t *testing.T) {
	runFailbackTest(t, "noswitch", "", false)
}

// TestFailback_SwitchWriter additionally moves the Aurora writer back to
// region 0, returning the deployment to its pre-failover shape.
func TestFailback_SwitchWriter(t *testing.T) {
	runFailbackTest(t, "switch", "--switch-writer", true)
}

func runFailbackTest(t *testing.T, label, failbackFlag string, expectWriterMovesBack bool) {
	t.Helper()

	f := helpers.NewFixture(t, "failback-"+label, "transit_gateway", "rdbms")

	// ApplyAllThreeStates registers each state's destroy with t.Cleanup, so a
	// failure partway through still tears down what was created.
	_, _, appOpts := helpers.ApplyAllThreeStates(t, f.Paths, f.Options)

	env := helpers.ProcedureEnv(t, f.ProcedureDir, f.Paths.Infra, f.AWSProfile)
	globalClusterID := env["AURORA_GLOBAL_CLUSTER_ID"]

	albEndpoint0 := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	albEndpoint1 := terraform.Output(t, appOpts, "region_1_alb_endpoint")
	require.NotEmpty(t, albEndpoint1)

	// Baseline quorum across both regions.
	before := helpers.WaitForRaftQuorum(t, albEndpoint0, env["ADMIN_USER"], env["ADMIN_PASS"],
		brokersBothZones, partitionCount, f.RaftTimeout)
	require.Equal(t, rfBothZones, before.ReplicationFactor, "baseline replication factor")

	// Step 1: take region 0 out of service via the runbook — scale its tasks
	// to zero, promote the region 1 database, and force-remove region 0's zone
	// from the partition distribution.
	helpers.RunProcedureScript(t, f.Procedure("failover.sh"), env, "--failed-region", "0")
	helpers.RequireRegionScaledDown(t, f.AWSProfile, f.Region0, env["CLUSTER_0"])

	// Mid-flight: one zone, so half the replicas.
	during := helpers.WaitForRaftQuorum(t, albEndpoint1, env["ADMIN_USER"], env["ADMIN_PASS"],
		brokersOneZone, partitionCount, 15*time.Minute)
	require.Equal(t, rfOneZone, during.ReplicationFactor,
		"after failover: the removed zone's replicas should be gone")

	// failover.sh promoted the writer as part of step 1; assert the
	// precondition rather than creating it.
	require.Equal(t, f.Region1, helpers.AuroraWriterRegion(t, f.AWSProfile, globalClusterID),
		"precondition for failback: failover.sh should have moved the writer to region 1")

	// Step 2: failback.
	args := []string{"--failed-region", "0"}
	if failbackFlag != "" {
		args = append(args, failbackFlag)
	}
	helpers.RunProcedureScript(t, f.Procedure("failback.sh"), env, args...)

	// Assertion 1: region 0 is serving again and the cluster is whole.
	// failback.sh re-adds the zone and waits for this itself, so a short
	// budget is enough here.
	after := helpers.WaitForRaftQuorum(t, albEndpoint0, env["ADMIN_USER"], env["ADMIN_PASS"],
		brokersBothZones, partitionCount, 15*time.Minute)
	require.Equal(t, rfBothZones, after.ReplicationFactor,
		"after failback: the zone must be back in the persisted distribution, not merely "+
			"running brokers — %d brokers with a factor of %d would mean they host no partitions",
		brokersBothZones, rfOneZone)

	// Assertion 2: the writer sits where this variant expects.
	finalWriter := helpers.AuroraWriterRegion(t, f.AWSProfile, globalClusterID)
	if expectWriterMovesBack {
		require.Equal(t, f.Region0, finalWriter,
			"failback %s: writer should move back to region 0", label)
	} else {
		require.Equal(t, f.Region1, finalWriter,
			"failback %s: writer should remain in region 1 (no --switch-writer)", label)
	}
}
