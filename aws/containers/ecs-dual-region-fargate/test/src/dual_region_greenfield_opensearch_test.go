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
	topo := helpers.WaitForRaftQuorum(t, albEndpoint, "admin", adminPass, 8, 8, f.RaftTimeout)

	require.Len(t, topo.Brokers, 8, "expected 8 Zeebe brokers (4 per region)")
	require.Equal(t, 8, topo.PartitionsCount, "expected 8 partitions")
	require.Equal(t, 4, topo.ReplicationFactor, "expected replication factor 4")
}
