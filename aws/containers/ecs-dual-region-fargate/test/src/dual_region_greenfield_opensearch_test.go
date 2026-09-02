// End-to-end test: greenfield ECS dual-region with VPC Peering + OpenSearch.
//
// The complement to TestEndToEnd_Greenfield_TGW_RDBMS — exercises the other
// secondary storage path and the alternative networking mode in one go.

package src

import (
	"fmt"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"

	"github.com/camunda/camunda-deployment-references/aws/containers/ecs-dual-region-fargate/test/src/helpers"
)

func TestEndToEnd_Greenfield_VpcPeering_OpenSearch(t *testing.T) {
	t.Parallel()

	awsProfile := envOrDefault("TEST_AWS_PROFILE", "infraex")
	region0 := envOrDefault("TEST_REGION_0", "eu-west-2")
	region1 := envOrDefault("TEST_REGION_1", "eu-west-3")
	clusterPrefix := envOrDefault("TEST_CLUSTER_PREFIX", fmt.Sprintf("e2e-peer-os-%s", strings.ToLower(random.UniqueId())))
	raftTimeoutMin := envIntOrDefault(t, "TEST_RAFT_TIMEOUT_MIN", 30)
	backendBucket := envOrDefault("TEST_BACKEND_BUCKET", "tests-ra-aws-rosa-hcp-tf-state-eu-central-1")
	backendRegion := envOrDefault("TEST_BACKEND_REGION", "eu-central-1")

	_, thisFile, _, _ := runtime.Caller(0)
	paths := helpers.DefaultStatePaths(filepath.Dir(thisFile))

	commonTags := map[string]interface{}{
		"Test":    "true",
		"RunID":   clusterPrefix,
		"Owner":   "terratest",
		"Purpose": "ecs-dual-region-e2e-greenfield-peering-opensearch",
	}

	opts := helpers.ApplyOptions{
		VPCVars: map[string]interface{}{
			"cluster_name":       clusterPrefix,
			"aws_profile":        awsProfile,
			"region_0":           region0,
			"region_1":           region1,
			"networking_mode":    "vpc_peering",
			"single_nat_gateway": true,
			"default_tags":       commonTags,
		},
		InfraVars: map[string]interface{}{
			"cluster_name":           clusterPrefix,
			"aws_profile":            awsProfile,
			"region_0":               region0,
			"region_1":               region1,
			"secondary_storage_type": "opensearch",
			"s3_force_destroy":       true,
			"default_tags":           commonTags,
		},
		AppVars: map[string]interface{}{
			"aws_profile":  awsProfile,
			"default_tags": commonTags,
		},
		BackendBucket:    backendBucket,
		BackendRegion:    backendRegion,
		BackendKeyPrefix: fmt.Sprintf("aws/containers/ecs-dual-region-fargate/%s/", clusterPrefix),
	}

	var vpcOpts, infraOpts, appOpts *terraform.Options
	defer helpers.DestroyAllThreeStates(t, appOpts, infraOpts, vpcOpts)

	vpcOpts, infraOpts, appOpts = helpers.ApplyAllThreeStates(t, paths, opts)

	albEndpoint := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	require.NotEmpty(t, albEndpoint, "region_0_alb_endpoint should be a non-empty DNS name")

	t.Logf("Waiting for Raft quorum at %s ...", albEndpoint)
	topo := helpers.WaitForRaftQuorum(t, albEndpoint, 8, 8, time.Duration(raftTimeoutMin)*time.Minute)

	require.Len(t, topo.Brokers, 8, "expected 8 Zeebe brokers (4 per region)")
	require.Equal(t, 8, topo.PartitionsCount, "expected 8 partitions")
	require.Equal(t, 4, topo.ReplicationFactor, "expected replication factor 4")
}
