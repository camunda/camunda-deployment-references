// End-to-end test: BYO-VPC mode.
//
// Creates two throwaway VPCs via aws/test-fixtures/byo-vpcs/, plugs their
// IDs into the ecs-dual-region-fargate vpc/ state with byo_vpc = true,
// applies infra/ and app/, waits for Raft quorum, destroys everything in
// reverse order (app -> infra -> vpc -> fixture VPCs).
//
// Costs ~$60–110 per run (greenfield + BYO fixture overhead). Sandbox only.

package src

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"

	"github.com/camunda/camunda-deployment-references/aws/containers/ecs-dual-region-fargate/test/src/helpers"
)

func TestEndToEnd_BYO_VPC_TGW_RDBMS(t *testing.T) {
	f := helpers.NewFixture(t, "byo-vpc", "transit_gateway", "rdbms")

	// Step 1: stand up the throwaway VPCs that stand in for a customer-owned pair.
	vpcs := helpers.SetupBYOVPCs(t, f.CallerDir, f.ClusterPrefix, f.AWSProfile, f.Region0, f.Region1, f.Tags)
	// t.Cleanup, not defer: a function's defers run *before* the testing
	// framework's cleanups, so `defer` here destroyed the customer VPCs while
	// app/infra/vpc were still standing in them — every dependent destroy then
	// failed and leaked. Registering before ApplyAllThreeStates puts this last
	// in LIFO order, which is exactly when it should run.
	t.Cleanup(func() { vpcs.DestroyBYOVPCs(t) })

	// Step 2: switch the vpc/ layer to consume them instead of creating its own.
	f.Options.VPCVars["byo_vpc"] = true
	delete(f.Options.VPCVars, "single_nat_gateway") // no NAT to create in BYO mode
	for k, v := range vpcs.ToTFVars(t) {
		f.Options.VPCVars[k] = v
	}

	// ApplyAllThreeStates registers each state's destroy with t.Cleanup, so a
	// failure partway through still tears down what was created.
	vpcOpts, _, appOpts := helpers.ApplyAllThreeStates(t, f.Paths, f.Options)

	albEndpoint := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	require.NotEmpty(t, albEndpoint)

	adminPass := helpers.SensitiveOutput(t, appOpts, "admin_user_password")
	require.NotEmpty(t, adminPass, "admin_user_password is needed to poll /v2/topology")

	t.Logf("Waiting for Raft quorum at %s ...", albEndpoint)
	topo := helpers.WaitForRaftQuorum(t, albEndpoint, "admin", adminPass, brokersBothZones, partitionCount, f.RaftTimeout)

	require.Len(t, topo.Brokers, brokersBothZones)
	require.Equal(t, partitionCount, topo.PartitionsCount)
	require.Equal(t, rfBothZones, topo.ReplicationFactor)

	// BYO-specific assertion: the vpc/ state should re-export the supplied VPC IDs.
	require.Equal(t,
		vpcs.ToTFVars(t)["region_0_vpc_id"],
		terraform.Output(t, vpcOpts, "region_0_vpc_id"),
		"vpc/ state should re-export the supplied region_0_vpc_id in BYO mode")
}
