// End-to-end test: greenfield ECS dual-region with VPC Peering + OpenSearch.
//
// The complement to TestEndToEnd_Greenfield_TGW_RDBMS — exercises the other
// secondary storage path and the alternative networking mode in one go.

package src

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"

	"github.com/camunda/camunda-deployment-references/aws/containers/ecs-dual-region-fargate/test/src/helpers"
)

func TestEndToEnd_Greenfield_VpcPeering_OpenSearch(t *testing.T) {
	f := helpers.NewFixture(t, "greenfield-peering-opensearch", "vpc_peering", "opensearch")

	var vpcOpts, infraOpts, appOpts *terraform.Options
	defer helpers.DestroyAllThreeStates(t, appOpts, infraOpts, vpcOpts)

	vpcOpts, infraOpts, appOpts = helpers.ApplyAllThreeStates(t, f.Paths, f.Options)

	albEndpoint := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	require.NotEmpty(t, albEndpoint, "region_0_alb_endpoint should be a non-empty DNS name")

	adminPass := terraform.Output(t, appOpts, "admin_user_password")
	require.NotEmpty(t, adminPass, "admin_user_password is needed to poll /v2/topology")

	t.Logf("Waiting for Raft quorum at %s ...", albEndpoint)
	topo := helpers.WaitForRaftQuorum(t, albEndpoint, "admin", adminPass, brokersBothZones, partitionCount, f.RaftTimeout)

	require.Len(t, topo.Brokers, brokersBothZones, "expected %d Zeebe brokers (%d per region)", brokersBothZones, brokersOneZone)
	require.Equal(t, partitionCount, topo.PartitionsCount, "expected %d partitions", partitionCount)
	require.Equal(t, rfBothZones, topo.ReplicationFactor, "expected replication factor %d", rfBothZones)
}
