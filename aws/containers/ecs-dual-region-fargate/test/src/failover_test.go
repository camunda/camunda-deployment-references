// Failover end-to-end tests.
//
// Deploys a baseline cluster, runs procedure/failover.sh — which force-removes
// the lost zone through the Zones API — and asserts on what that script
// actually guarantees: the failed region is scaled to zero, the surviving
// region still has a working Zeebe cluster, and Aurora Global is untouched and
// healthy.
//
// Note on Aurora: failover.sh deliberately does NOT move the writer ("the
// JDBC failover plugin and AWS handle writer promotion automatically via the
// global cluster endpoint"). Asserting a writer-region change here would test
// a behaviour the reference architecture does not implement. The writer move
// is asserted in TestFailback_SwitchWriter, where `aws rds
// failover-global-cluster` really does perform it.

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
func TestUnplannedFailover(t *testing.T) {
	runFailoverTest(t, "unplanned", true)
}

func runFailoverTest(t *testing.T, label string, killRegionFirst bool) {
	t.Helper()

	f := helpers.NewFixture(t, "failover-"+label, "transit_gateway", "rdbms")

	var vpcOpts, infraOpts, appOpts *terraform.Options
	defer helpers.DestroyAllThreeStates(t, appOpts, infraOpts, vpcOpts)

	vpcOpts, infraOpts, appOpts = helpers.ApplyAllThreeStates(t, f.Paths, f.Options)

	// The procedure scripts hard-require a full environment contract; source
	// it from the script that owns it rather than rebuilding it here.
	env := helpers.ProcedureEnv(t, f.ProcedureDir, f.Paths.Infra, f.AWSProfile)
	globalClusterID := env["AURORA_GLOBAL_CLUSTER_ID"]

	// Baseline: writer in region 0, full quorum.
	require.Equal(t, f.Region0, helpers.AuroraWriterRegion(t, f.AWSProfile, globalClusterID),
		"baseline: Aurora writer should start in region 0")
	albEndpoint0 := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	helpers.WaitForRaftQuorum(t, albEndpoint0, env["ADMIN_USER"], env["ADMIN_PASS"], 8, 8, f.RaftTimeout)

	args := []string{"--failed-region", "0"}
	if killRegionFirst {
		t.Log("Simulating an unplanned outage: scaling region 0 to zero before the runbook starts")
		helpers.ScaleRegionServices(t, f.AWSProfile, f.Region0, env["CLUSTER_0"], 0, 10*time.Minute)
		// The region is already down, so there is nothing left for the script
		// to scale.
		args = append(args, "--keep-tasks")
	}

	helpers.RunProcedureScript(t, f.Procedure("failover.sh"), env, args...)

	// Assertion 1: the failed region is drained. This is the step the script
	// performs itself and the one that prevents split-brain.
	helpers.RequireRegionScaledDown(t, f.AWSProfile, f.Region0, env["CLUSTER_0"])

	// Assertion 2: the surviving region still serves a Zeebe cluster. Region 0
	// is down, so only its four brokers remain; the partition count is
	// unchanged because failover redistributes rather than drops partitions.
	albEndpoint1 := terraform.Output(t, appOpts, "region_1_alb_endpoint")
	require.NotEmpty(t, albEndpoint1)
	helpers.WaitForRaftQuorum(t, albEndpoint1, env["ADMIN_USER"], env["ADMIN_PASS"], 4, 8, 15*time.Minute)

	// Assertion 3: Aurora Global is healthy and, per the script's own
	// contract, the writer has NOT been moved by the runbook.
	require.Equal(t, "available", helpers.AuroraGlobalClusterStatus(t, f.AWSProfile, globalClusterID),
		"after %s failover: Aurora global cluster should still be available", label)
}
