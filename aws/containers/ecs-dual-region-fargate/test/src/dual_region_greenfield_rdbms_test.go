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
	"fmt"
	"os"
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

func TestEndToEnd_Greenfield_TGW_RDBMS(t *testing.T) {
	t.Parallel()

	awsProfile := envOrDefault("TEST_AWS_PROFILE", "infraex")
	region0 := envOrDefault("TEST_REGION_0", "eu-west-2")
	region1 := envOrDefault("TEST_REGION_1", "eu-west-3")
	clusterPrefix := envOrDefault("TEST_CLUSTER_PREFIX", fmt.Sprintf("e2e-tgw-rdbms-%s", strings.ToLower(random.UniqueId())))
	raftTimeoutMin := envIntOrDefault(t, "TEST_RAFT_TIMEOUT_MIN", 30)

	// Resolve state paths relative to THIS test file's directory.
	_, thisFile, _, _ := runtime.Caller(0)
	paths := helpers.DefaultStatePaths(filepath.Dir(thisFile))

	commonTags := map[string]interface{}{
		"Test":    "true",
		"RunID":   clusterPrefix,
		"Owner":   "terratest",
		"Purpose": "ecs-dual-region-e2e-greenfield-tgw-rdbms",
	}

	opts := helpers.ApplyOptions{
		VPCVars: map[string]interface{}{
			"cluster_name":       clusterPrefix,
			"aws_profile":        awsProfile,
			"region_0":           region0,
			"region_1":           region1,
			"networking_mode":    "transit_gateway",
			"single_nat_gateway": true,
			"default_tags":       commonTags,
		},
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

	// Read region 0 ALB endpoint from the app state (it re-exports infra outputs).
	albEndpoint := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	require.NotEmpty(t, albEndpoint, "region_0_alb_endpoint should be a non-empty DNS name")

	t.Logf("Waiting for Raft quorum at %s ...", albEndpoint)
	topo := helpers.WaitForRaftQuorum(t, albEndpoint, 8, 8, time.Duration(raftTimeoutMin)*time.Minute)

	require.Len(t, topo.Brokers, 8, "expected 8 Zeebe brokers (4 per region)")
	require.Equal(t, 8, topo.PartitionsCount, "expected 8 partitions")
	require.Equal(t, 4, topo.ReplicationFactor, "expected replication factor 4")
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envIntOrDefault(t *testing.T, key string, fallback int) int {
	t.Helper()
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	var parsed int
	if _, err := fmt.Sscanf(v, "%d", &parsed); err != nil {
		t.Fatalf("%s must be an integer, got %q", key, v)
	}
	return parsed
}
