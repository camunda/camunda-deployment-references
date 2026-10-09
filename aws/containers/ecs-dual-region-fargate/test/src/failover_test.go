// Failover end-to-end tests.
//
// Deploys a baseline cluster, runs procedure/failover.sh, and asserts the three
// things that runbook changes: the failed region's ECS services are drained,
// the Aurora Global writer is promoted out of the failed region, and the failed
// zone leaves the persisted partition distribution — visible as the replication
// factor falling (see doc.go for why the factor and not the broker count).
//
// See the folder README, "Failover / Failback", for why the writer has to move.

package src

import (
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"

	"github.com/camunda/camunda-deployment-references/aws/containers/ecs-dual-region-fargate/test/src/helpers"
)

// TestPlannedFailover is the graceful case: the operator runs failover.sh
// against a fully healthy deployment and lets it drain region 0 itself.
func TestPlannedFailover(t *testing.T) {
	runFailoverTest(t, "planned", false)
}

// TestUnplannedFailover is the outage case: region 0 is already gone by the
// time the operator reaches for the runbook.
//
// There is no --unplanned flag — failover.sh's parser rejects unknown
// arguments. The scenario is built from the flags that do exist: kill region 0
// out-of-band, then pass --keep-tasks, which is exactly the "region is already
// down, skip the ECS scale-down" case the script documents.
//
// Note what this does and does not simulate: region 0's *compute* is gone, but
// its Aurora cluster is still reachable, so the planned switchover in step 2
// still applies. A genuine loss of the database region cannot be switched over
// — failover-global-cluster needs the current writer to answer — and needs the
// AWS detach-and-promote procedure, which changes global-cluster membership
// outside Terraform and is out of scope for this suite.
func TestUnplannedFailover(t *testing.T) {
	runFailoverTest(t, "unplanned", true)
}

func runFailoverTest(t *testing.T, label string, killRegionFirst bool) {
	t.Helper()

	f := helpers.NewFixture(t, "failover-"+label, "transit_gateway", "rdbms")

	// ApplyAllThreeStates registers each state's destroy with t.Cleanup, so a
	// failure partway through still tears down what was created.
	_, _, appOpts := helpers.ApplyAllThreeStates(t, f.Paths, f.Options)

	// The procedure scripts hard-require a full environment contract; source
	// it from the script that owns it rather than rebuilding it here.
	env := helpers.ProcedureEnv(t, f.ProcedureDir, f.Paths.Infra, f.AWSProfile)
	globalClusterID := env["AURORA_GLOBAL_CLUSTER_ID"]

	albEndpoint0 := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	albEndpoint1 := terraform.Output(t, appOpts, "region_1_alb_endpoint")
	require.NotEmpty(t, albEndpoint1)

	// ---- Baseline -------------------------------------------------------
	require.Equal(t, f.Region0, helpers.AuroraWriterRegion(t, f.AWSProfile, globalClusterID),
		"baseline: Aurora writer should start in region 0")

	before := helpers.WaitForRaftQuorum(t, albEndpoint0, env["ADMIN_USER"], env["ADMIN_PASS"],
		brokersBothZones, partitionCount, f.RaftTimeout)
	require.Equal(t, rfBothZones, before.ReplicationFactor,
		"baseline: both zones contribute %d replicas each, so the factor is %d",
		rfOneZone, rfBothZones)

	// ---- Failover -------------------------------------------------------
	args := []string{"--failed-region", "0"}
	if killRegionFirst {
		t.Log("Simulating an unplanned outage: scaling region 0 to zero before the runbook starts")
		helpers.ScaleRegionServices(t, f.AWSProfile, f.Region0, env["CLUSTER_0"], 0, 10*time.Minute)
		// The region is already down, so there is nothing left for the script
		// to scale.
		args = append(args, "--keep-tasks")
	}

	helpers.RunProcedureScript(t, f.Procedure("failover.sh"), env, args...)

	// ---- Assertions -----------------------------------------------------

	// 1. The failed region is drained.
	helpers.RequireRegionScaledDown(t, f.AWSProfile, f.Region0, env["CLUSTER_0"])

	// 2. The database is writable from the surviving region. failover.sh
	//    promotes the survivor itself — AWS performs no planned switchover on
	//    its own, and the JDBC failover plugin can only find a writer that
	//    exists.
	require.Equal(t, f.Region1, helpers.AuroraWriterRegion(t, f.AWSProfile, globalClusterID),
		"after %s failover: the Aurora writer should have moved to region 1", label)
	require.Equal(t, "available", helpers.AuroraGlobalClusterStatus(t, f.AWSProfile, globalClusterID),
		"after %s failover: the Aurora global cluster should still be available", label)

	// 3. The surviving zone is the whole cluster now: every partition still
	//    led, and a replication factor that proves the zone left the
	//    distribution rather than merely going unreachable.
	//
	//    Not asserted: the broker count. The scaled-down region's brokers stay
	//    in cluster membership for a while, hosting zero replicas — a live run
	//    showed brokers=8, clusterSize=4, replicationFactor=2 right after the
	//    change. Waiting for 4 brokers would wait on ECS task teardown rather
	//    than on anything about the cluster.
	after := helpers.WaitForPartitionLeaders(t, albEndpoint1, env["ADMIN_USER"], env["ADMIN_PASS"],
		partitionCount, 15*time.Minute)
	// Pinned at both ends, so a separate "it fell" assertion would be
	// unfalsifiable: before is rfBothZones, after is rfOneZone.
	require.Equal(t, rfOneZone, after.ReplicationFactor,
		"after %s failover: the zone's %d replicas should be gone, leaving %d. A factor "+
			"still at %d means the zone is in the persisted distribution and quorum is "+
			"counting replicas that cannot answer", label, rfOneZone, rfOneZone, rfBothZones)
	require.Equal(t, partitionCount, after.PartitionsCount,
		"after %s failover: failover redistributes partitions, it does not drop them", label)
}
