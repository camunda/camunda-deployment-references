// Failback end-to-end tests.
//
// Sequence: deploy baseline -> failover -> failback, asserting that region 0
// comes back into service and that the Aurora writer settles where each
// --switch-writer variant says it should.
//
// Why the test moves the Aurora writer itself: procedure/failover.sh
// deliberately leaves Aurora alone, because in a genuine region loss AWS and
// the JDBC failover plugin promote the surviving member — that is not the
// runbook's job. The test reproduces that promotion explicitly, so the
// starting state matches a real outage. Without it the writer never leaves
// region 0, and the --switch-writer variants become indistinguishable: both
// would end with the writer in region 0 whatever the flag said.

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

	var vpcOpts, infraOpts, appOpts *terraform.Options
	defer helpers.DestroyAllThreeStates(t, appOpts, infraOpts, vpcOpts)

	vpcOpts, infraOpts, appOpts = helpers.ApplyAllThreeStates(t, f.Paths, f.Options)

	env := helpers.ProcedureEnv(t, f.ProcedureDir, f.Paths.Infra, f.AWSProfile)
	globalClusterID := env["AURORA_GLOBAL_CLUSTER_ID"]

	albEndpoint0 := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	albEndpoint1 := terraform.Output(t, appOpts, "region_1_alb_endpoint")
	require.NotEmpty(t, albEndpoint1)

	// Baseline quorum across both regions.
	helpers.WaitForRaftQuorum(t, albEndpoint0, env["ADMIN_USER"], env["ADMIN_PASS"], 8, 8, f.RaftTimeout)

	// Step 1: take region 0 out of service via the runbook — scale its tasks
	// to zero and force-remove its zone from the partition distribution.
	helpers.RunProcedureScript(t, f.Procedure("failover.sh"), env, "--failed-region", "0")
	helpers.RequireRegionScaledDown(t, f.AWSProfile, f.Region0, env["CLUSTER_0"])

	// Step 2: promote the region 1 database, standing in for what AWS does
	// during a real region loss.
	helpers.AuroraFailoverToRegion(t, f.AWSProfile, globalClusterID, f.Region1, 15*time.Minute)
	require.Equal(t, f.Region1, helpers.AuroraWriterRegion(t, f.AWSProfile, globalClusterID),
		"precondition for failback: writer must be in region 1")

	// Step 3: failback.
	args := []string{"--failed-region", "0"}
	if failbackFlag != "" {
		args = append(args, failbackFlag)
	}
	helpers.RunProcedureScript(t, f.Procedure("failback.sh"), env, args...)

	// Assertion 1: region 0 is serving again and the cluster is whole.
	// failback.sh re-adds the zone and waits for this itself — restored
	// brokers rejoin membership but host no partitions until the zone is
	// back — so a short budget is enough here.
	helpers.WaitForRaftQuorum(t, albEndpoint0, env["ADMIN_USER"], env["ADMIN_PASS"], 8, 8, 15*time.Minute)

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
