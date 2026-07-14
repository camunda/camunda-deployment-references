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

	// Initial quorum.
	albEndpoint0 := terraform.Output(t, appOpts, "region_0_alb_endpoint")
	helpers.WaitForRaftQuorum(t, albEndpoint0, 8, 8, time.Duration(raftTimeoutMin)*time.Minute)

	// Step 1: planned failover to region 1.
	env := map[string]string{
		"REGION_0":                 region0,
		"REGION_1":                 region1,
		"CLUSTER_NAME":             clusterPrefix,
		"AWS_PROFILE":              awsProfile,
		"AURORA_GLOBAL_CLUSTER_ID": globalClusterID,
	}
	helpers.RunProcedureScript(t, filepath.Join(procedureDir, "failover.sh"), env)
	require.Equal(t, region1, helpers.AuroraWriterRegion(t, awsProfile, globalClusterID),
		"after failover: writer should be in region 1")

	// Step 2: failback.
	args := []string{}
	if failbackFlag != "" {
		args = append(args, failbackFlag)
	}
	helpers.RunProcedureScript(t, filepath.Join(procedureDir, "failback.sh"), env, args...)

	finalWriter := helpers.AuroraWriterRegion(t, awsProfile, globalClusterID)
	if expectWriterMovesBack {
		require.Equal(t, region0, finalWriter,
			"failback %s: writer should move back to region 0", label)
	} else {
		require.Equal(t, region1, finalWriter,
			"failback %s: writer should remain in region 1 (no --switch-writer)", label)
	}
}
