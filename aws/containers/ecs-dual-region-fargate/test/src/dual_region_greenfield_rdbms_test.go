// End-to-end test: greenfield ECS dual-region with Transit Gateway + Aurora Global.
//
// Applies vpc/ → infra/ → app/ against real AWS. Waits for 8 Zeebe brokers to
// form quorum and verifies each partition has a leader. Destroys all three
// states on completion.
//
// Run locally:
//
//	cd aws/containers/ecs-dual-region-fargate/test/src
//	go test -v -timeout 90m -run TestEndToEnd_Greenfield_TGW_RDBMS ./...
//
// Costs ~$50–100 per run. Sandbox account only.

package src

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"

	"github.com/camunda/camunda-deployment-references/aws/containers/ecs-dual-region-fargate/test/src/helpers"
)

func TestEndToEnd_Greenfield_TGW_RDBMS(t *testing.T) {
	f := helpers.NewFixture(t, "greenfield-tgw-rdbms", "transit_gateway", "rdbms")

	// ApplyAllThreeStates registers each state's destroy with t.Cleanup, so a
	// failure partway through still tears down what was created.
	_, _, appOpts := helpers.ApplyAllThreeStates(t, f.Paths, f.Options)

	// Read region 0 ALB endpoint from the app state (it re-exports infra outputs).
	albEndpoint := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	require.NotEmpty(t, albEndpoint, "region_0_alb_endpoint should be a non-empty DNS name")

	adminPass := helpers.SensitiveOutput(t, appOpts, "admin_user_password")
	require.NotEmpty(t, adminPass, "admin_user_password is needed to poll /v2/topology")

	t.Logf("Waiting for Raft quorum at %s ...", albEndpoint)
	topo := helpers.WaitForRaftQuorum(t, albEndpoint, "admin", adminPass, brokersBothZones, partitionCount, f.RaftTimeout)

	require.Len(t, topo.Brokers, brokersBothZones, "expected %d Zeebe brokers (%d per region)", brokersBothZones, brokersOneZone)
	require.Equal(t, partitionCount, topo.PartitionsCount, "expected %d partitions", partitionCount)
	require.Equal(t, rfBothZones, topo.ReplicationFactor, "expected replication factor %d", rfBothZones)
}
