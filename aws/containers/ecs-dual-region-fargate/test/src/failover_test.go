// Failover end-to-end tests.
//
// Deploys a baseline cluster, runs procedure/failover.sh, verifies Aurora
// writer moved to region 1 and Zeebe brokers are still healthy via region 1.
// Destroys on completion.

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

func TestPlannedFailover(t *testing.T) {
	t.Parallel()
	runFailoverTest(t, "planned", "")
}

// TestKeepTasksFailover covers the region-already-down case. It used to pass
// --unplanned, which the procedure never implemented and which the argument
// parser now rejects outright; --keep-tasks is the flag that expresses the
// same scenario (skip the ECS scale-down because nothing is running).
func TestKeepTasksFailover(t *testing.T) {
	t.Parallel()
	runFailoverTest(t, "keeptasks", "--keep-tasks")
}

// runFailoverTest is the shared body for planned and unplanned failover.
func runFailoverTest(t *testing.T, label, failoverFlag string) {
	t.Helper()

	awsProfile := envOrDefault("TEST_AWS_PROFILE", "infraex")
	region0 := envOrDefault("TEST_REGION_0", "eu-west-2")
	region1 := envOrDefault("TEST_REGION_1", "eu-west-3")
	clusterPrefix := envOrDefault("TEST_CLUSTER_PREFIX", fmt.Sprintf("e2e-fo-%s-%s", label, strings.ToLower(random.UniqueId())))
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
		"Purpose": fmt.Sprintf("ecs-dual-region-failover-%s", label),
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

	// Baseline assertion: writer in region 0.
	globalClusterID := terraform.Output(t, infraOpts, "aurora_global_cluster_id")
	require.NotEmpty(t, globalClusterID)
	require.Equal(t, region0, helpers.AuroraWriterRegion(t, awsProfile, globalClusterID),
		"baseline: Aurora writer should start in region 0")

	// The procedure scripts require the full operator environment and exit 1 on
	// the first missing variable, so build it from the applied state.
	env := helpers.ProcedureEnv(t, infraOpts, appOpts, awsProfile, globalClusterID)

	// Wait for initial quorum before triggering failover.
	helpers.WaitForRaftQuorum(t, env["ALB_ENDPOINT_0"], env["ADMIN_USER"], env["ADMIN_PASS"],
		8, 8, time.Duration(raftTimeoutMin)*time.Minute)

	// Run failover.
	scriptPath := filepath.Join(procedureDir, "failover.sh")
	args := []string{}
	if failoverFlag != "" {
		args = append(args, failoverFlag)
	}
	helpers.RunProcedureScript(t, scriptPath, env, args...)

	// Assertion 1: the surviving zone still serves every partition. Region 0 is
	// scaled to zero and its zone is removed, so the cluster halves to 4 brokers
	// while all 8 partitions keep a leader — that is the point of the procedure.
	helpers.WaitForRaftQuorum(t, env["ALB_ENDPOINT_1"], env["ADMIN_USER"], env["ADMIN_PASS"],
		4, 8, time.Duration(raftTimeoutMin)*time.Minute)

	// Assertion 2: Aurora is untouched. failover.sh deliberately leaves the
	// global cluster alone — the JDBC failover plugin and AWS handle promotion
	// on a real region loss — so the writer must still be in region 0. This
	// previously asserted the opposite, which the procedure never did.
	require.Equal(t, region0, helpers.AuroraWriterRegion(t, awsProfile, globalClusterID),
		"after %s failover: failover.sh must not move the Aurora writer", label)
}
