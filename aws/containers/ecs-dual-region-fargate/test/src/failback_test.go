// Failback end-to-end tests.
//
// Deploy baseline -> failover -> failback. Assert Aurora writer settles in
// the expected region for each --switch-writer variant.

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

func TestFailback_NoSwitchWriter(t *testing.T) {
	t.Parallel()
	runFailbackTest(t, "noswitch", "", false)
}

func TestFailback_SwitchWriter(t *testing.T) {
	t.Parallel()
	runFailbackTest(t, "switch", "--switch-writer", true)
}

func runFailbackTest(t *testing.T, label, failbackFlag string, expectWriterMovesBack bool) {
	t.Helper()

	awsProfile := envOrDefault("TEST_AWS_PROFILE", "infraex")
	region0 := envOrDefault("TEST_REGION_0", "eu-west-2")
	region1 := envOrDefault("TEST_REGION_1", "eu-west-3")
	clusterPrefix := envOrDefault("TEST_CLUSTER_PREFIX", fmt.Sprintf("e2e-fb-%s-%s", label, strings.ToLower(random.UniqueId())))
	raftTimeoutMin := envIntOrDefault(t, "TEST_RAFT_TIMEOUT_MIN", 30)
	backendBucket := envOrDefault("TEST_BACKEND_BUCKET", "tests-ra-aws-rosa-hcp-tf-state-eu-central-1")
	backendRegion := envOrDefault("TEST_BACKEND_REGION", "eu-central-1")

	_, thisFile, _, _ := runtime.Caller(0)
	thisDir := filepath.Dir(thisFile)
	paths := helpers.DefaultStatePaths(thisDir)
	procedureDir := filepath.Join(thisDir, "..", "..", "procedure")

	commonTags := map[string]interface{}{
		"Test":    "true",
		"RunID":   clusterPrefix,
		"Owner":   "terratest",
		"Purpose": fmt.Sprintf("ecs-dual-region-failback-%s", label),
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
		BackendBucket:    backendBucket,
		BackendRegion:    backendRegion,
		BackendKeyPrefix: fmt.Sprintf("aws/containers/ecs-dual-region-fargate/%s/", clusterPrefix),
	}

	var vpcOpts, infraOpts, appOpts *terraform.Options
	defer helpers.DestroyAllThreeStates(t, appOpts, infraOpts, vpcOpts)

	vpcOpts, infraOpts, appOpts = helpers.ApplyAllThreeStates(t, paths, opts)

	globalClusterID := terraform.Output(t, infraOpts, "aurora_global_cluster_id")
	require.NotEmpty(t, globalClusterID)

	// The procedure scripts require the full operator environment and exit 1 on
	// the first missing variable, so build it from the applied state.
	env := helpers.ProcedureEnv(t, infraOpts, appOpts, awsProfile, globalClusterID)

	// Initial quorum.
	helpers.WaitForRaftQuorum(t, env["ALB_ENDPOINT_0"], env["ADMIN_USER"], env["ADMIN_PASS"],
		8, 8, time.Duration(raftTimeoutMin)*time.Minute)

	// Step 1: fail region 0 away. The zone is removed and the cluster halves to
	// 4 brokers, all 8 partitions still led from region 1.
	helpers.RunProcedureScript(t, filepath.Join(procedureDir, "failover.sh"), env)
	helpers.WaitForRaftQuorum(t, env["ALB_ENDPOINT_1"], env["ADMIN_USER"], env["ADMIN_PASS"],
		4, 8, time.Duration(raftTimeoutMin)*time.Minute)

	// failover.sh does not touch Aurora, so the writer is still in region 0.
	require.Equal(t, region0, helpers.AuroraWriterRegion(t, awsProfile, globalClusterID),
		"failover.sh must not move the Aurora writer")

	// --switch-writer only has something to switch if the writer actually left
	// region 0, which on a real region loss is AWS promoting the survivor.
	// Simulate that here; without it the flag is a no-op and the test asserts
	// nothing, which is what it used to do.
	if expectWriterMovesBack {
		helpers.PromoteAuroraWriter(t, awsProfile, globalClusterID, region1)
	}

	// Step 2: failback.
	args := []string{}
	if failbackFlag != "" {
		args = append(args, failbackFlag)
	}
	helpers.RunProcedureScript(t, filepath.Join(procedureDir, "failback.sh"), env, args...)

	// Both zones are back, so the full cluster is expected again.
	helpers.WaitForRaftQuorum(t, env["ALB_ENDPOINT_0"], env["ADMIN_USER"], env["ADMIN_PASS"],
		8, 8, time.Duration(raftTimeoutMin)*time.Minute)

	finalWriter := helpers.AuroraWriterRegion(t, awsProfile, globalClusterID)
	if expectWriterMovesBack {
		require.Equal(t, region0, finalWriter,
			"failback %s: --switch-writer should bring the writer back to region 0", label)
	} else {
		require.Equal(t, region0, finalWriter,
			"failback %s: without --switch-writer the writer stays where it was", label)
	}
}
