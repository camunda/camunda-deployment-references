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

func TestEndToEnd_BYO_VPC_TGW_RDBMS(t *testing.T) {
	t.Parallel()

	awsProfile := envOrDefault("TEST_AWS_PROFILE", "infraex")
	region0 := envOrDefault("TEST_REGION_0", "eu-west-2")
	region1 := envOrDefault("TEST_REGION_1", "eu-west-3")
	clusterPrefix := envOrDefault("TEST_CLUSTER_PREFIX", fmt.Sprintf("e2e-byo-%s", strings.ToLower(random.UniqueId())))
	raftTimeoutMin := envIntOrDefault(t, "TEST_RAFT_TIMEOUT_MIN", 30)

	_, thisFile, _, _ := runtime.Caller(0)
	thisDir := filepath.Dir(thisFile)
	paths := helpers.DefaultStatePaths(thisDir)

	commonTags := map[string]interface{}{
		"Test":    "true",
		"RunID":   clusterPrefix,
		"Owner":   "terratest",
		"Purpose": "ecs-dual-region-e2e-byo-vpc",
	}

	// Step 1: Spin up the throwaway VPCs that simulate a customer-owned VPC pair.
	fixture := helpers.SetupBYOVPCs(t, thisDir, clusterPrefix, awsProfile, region0, region1, commonTags)
	defer fixture.DestroyBYOVPCs(t)

	// Build the vpc/ tfvars: byo_vpc = true + the fixture outputs.
	vpcVars := map[string]interface{}{
		"cluster_name":    clusterPrefix,
		"aws_profile":     awsProfile,
		"region_0":        region0,
		"region_1":        region1,
		"networking_mode": "transit_gateway",
		"byo_vpc":         true,
		"default_tags":    commonTags,
	}
	for k, v := range fixture.ToTFVars(t) {
		vpcVars[k] = v
	}

	opts := helpers.ApplyOptions{
		VPCVars: vpcVars,
		InfraVars: map[string]interface{}{
			"cluster_name":           clusterPrefix,
			"aws_profile":            awsProfile,
			"region_0":               region0,
			"region_1":               region1,
			"secondary_storage_type": "rdbms",
			"s3_force_destroy":       true,
			"default_tags":           commonTags,
		},
		AppVars: map[string]interface{}{
			"aws_profile":  awsProfile,
			"default_tags": commonTags,
		},
	}

	var vpcOpts, infraOpts, appOpts *terraform.Options
	defer helpers.DestroyAllThreeStates(t, appOpts, infraOpts, vpcOpts)

	vpcOpts, infraOpts, appOpts = helpers.ApplyAllThreeStates(t, paths, opts)

	albEndpoint := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	require.NotEmpty(t, albEndpoint)

	t.Logf("Waiting for Raft quorum at %s ...", albEndpoint)
	topo := helpers.WaitForRaftQuorum(t, albEndpoint, 8, 8, time.Duration(raftTimeoutMin)*time.Minute)

	require.Len(t, topo.Brokers, 8)
	require.Equal(t, 8, topo.PartitionsCount)
	require.Equal(t, 4, topo.ReplicationFactor)

	// BYO-specific assertion: the vpc/ state should re-export the supplied VPC IDs.
	require.Equal(t,
		fixture.ToTFVars(t)["region_0_vpc_id"],
		terraform.Output(t, vpcOpts, "region_0_vpc_id"),
		"vpc/ state should re-export the supplied region_0_vpc_id in BYO mode")
}
