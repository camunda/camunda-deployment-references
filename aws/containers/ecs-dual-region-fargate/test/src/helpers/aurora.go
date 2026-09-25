// Aurora Global helpers — used by failover/failback tests to assert on
// writer region changes. Shells out to `aws rds describe-global-clusters`
// rather than pulling in the AWS SDK to keep dependency footprint small.
package helpers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

type globalClusterMember struct {
	DBClusterArn string `json:"DBClusterArn"`
	IsWriter     bool   `json:"IsClusterWriter"`
}

// AuroraWriterRegion returns the AWS region (e.g. "eu-west-2") of the current
// writer cluster in the specified Aurora Global cluster. Fails the test if
// the writer member can't be found or the CLI call errors out.
func AuroraWriterRegion(t *testing.T, awsProfile, globalClusterID string) string {
	t.Helper()
	args := []string{
		"rds", "describe-global-clusters",
		"--global-cluster-identifier", globalClusterID,
		"--query", "GlobalClusters[0].GlobalClusterMembers",
		"--output", "json",
	}
	if awsProfile != "" {
		args = append(args, "--profile", awsProfile)
	}

	var stdout bytes.Buffer
	cmd := exec.Command("aws", args...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stdout
	if err := cmd.Run(); err != nil {
		t.Fatalf("aws rds describe-global-clusters failed: %v\n%s", err, stdout.String())
	}

	var members []globalClusterMember
	if err := json.Unmarshal(stdout.Bytes(), &members); err != nil {
		t.Fatalf("parse describe-global-clusters JSON: %v\n%s", err, stdout.String())
	}

	for _, m := range members {
		if m.IsWriter {
			region := regionFromDBClusterARN(m.DBClusterArn)
			if region == "" {
				t.Fatalf("could not extract region from writer ARN %q", m.DBClusterArn)
			}
			return region
		}
	}
	t.Fatalf("no writer member found in global cluster %s", globalClusterID)
	return "" // unreachable
}

// regionFromDBClusterARN extracts the region from an ARN of the form
// "arn:aws:rds:<region>:<account>:cluster:<id>".
func regionFromDBClusterARN(arn string) string {
	parts := strings.Split(arn, ":")
	if len(parts) < 4 {
		return ""
	}
	return parts[3]
}

// RunProcedureScript runs one of the procedure/*.sh scripts with the supplied
// environment (see ProcedureEnv). Fails the test on non-zero exit.
func RunProcedureScript(t *testing.T, scriptPath string, env map[string]string, extraArgs ...string) {
	t.Helper()

	cmd := exec.Command(scriptPath, extraArgs...)
	cmd.Env = append(cmd.Env, dockerSafeOSEnv()...)
	for k, v := range env {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	var combined bytes.Buffer
	cmd.Stdout = &combined
	cmd.Stderr = &combined
	t.Logf("Running %s %v", scriptPath, extraArgs)
	if err := cmd.Run(); err != nil {
		t.Fatalf("%s failed: %v\n%s", scriptPath, err, combined.String())
	}
	t.Logf("%s succeeded:\n%s", scriptPath, combined.String())
}

// dockerSafeOSEnv returns the host's PATH so child processes can find aws,
// terraform, etc., without inheriting the entire test environment.
func dockerSafeOSEnv() []string {
	return []string{"PATH=" + os.Getenv("PATH")}
}

// PromoteAuroraWriter performs a planned switchover of the Aurora Global
// writer to the cluster member in targetRegion, then waits for the global
// cluster to settle.
//
// The failover procedure deliberately does not touch Aurora — the JDBC
// failover plugin and AWS handle promotion on a real region loss. A test that
// wants to exercise failback's --switch-writer therefore has to create that
// starting condition itself, otherwise the writer never leaves region 0 and
// "switch it back" asserts nothing.
func PromoteAuroraWriter(t *testing.T, awsProfile, globalClusterID, targetRegion string) {
	t.Helper()

	memberARN := auroraMemberARN(t, awsProfile, globalClusterID, targetRegion)
	args := []string{
		"rds", "failover-global-cluster",
		"--global-cluster-identifier", globalClusterID,
		"--target-db-cluster-identifier", memberARN,
		"--no-cli-pager",
	}
	if awsProfile != "" {
		args = append(args, "--profile", awsProfile)
	}

	var out bytes.Buffer
	cmd := exec.Command("aws", args...)
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("aws rds failover-global-cluster to %s failed: %v\n%s", targetRegion, err, out.String())
	}

	deadline := time.Now().Add(15 * time.Minute)
	for time.Now().Before(deadline) {
		if AuroraWriterRegion(t, awsProfile, globalClusterID) == targetRegion {
			t.Logf("Aurora writer promoted to %s", targetRegion)
			return
		}
		time.Sleep(30 * time.Second)
	}
	t.Fatalf("timed out waiting for the Aurora writer to move to %s", targetRegion)
}

// auroraMemberARN returns the global-cluster member ARN that lives in region.
func auroraMemberARN(t *testing.T, awsProfile, globalClusterID, region string) string {
	t.Helper()
	args := []string{
		"rds", "describe-global-clusters",
		"--global-cluster-identifier", globalClusterID,
		"--query", "GlobalClusters[0].GlobalClusterMembers",
		"--output", "json",
	}
	if awsProfile != "" {
		args = append(args, "--profile", awsProfile)
	}

	var stdout bytes.Buffer
	cmd := exec.Command("aws", args...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stdout
	if err := cmd.Run(); err != nil {
		t.Fatalf("aws rds describe-global-clusters failed: %v\n%s", err, stdout.String())
	}

	var members []globalClusterMember
	if err := json.Unmarshal(stdout.Bytes(), &members); err != nil {
		t.Fatalf("parse describe-global-clusters JSON: %v\n%s", err, stdout.String())
	}
	for _, m := range members {
		if regionFromDBClusterARN(m.DBClusterArn) == region {
			return m.DBClusterArn
		}
	}
	t.Fatalf("no global-cluster member found in region %s", region)
	return "" // unreachable
}

// ProcedureEnv builds the environment the procedure scripts require.
//
// failover.sh and failback.sh both assert on REGION_*, CLUSTER_*,
// ALB_ENDPOINT_*, ADMIN_USER and ADMIN_PASS up front and exit 1 if any is
// missing, which is exactly what export_environment_prerequisites.sh exports
// for a human operator. Building it in one place keeps the two tests from
// drifting away from the scripts again.
func ProcedureEnv(t *testing.T, infraOpts, appOpts *terraform.Options, awsProfile, globalClusterID string) map[string]string {
	t.Helper()

	clusterFromARN := func(arn string) string {
		if i := strings.LastIndex(arn, "/"); i >= 0 {
			return arn[i+1:]
		}
		return arn
	}

	env := map[string]string{
		"REGION_0":                 terraform.Output(t, infraOpts, "region_0"),
		"REGION_1":                 terraform.Output(t, infraOpts, "region_1"),
		"CLUSTER_0":                clusterFromARN(terraform.Output(t, infraOpts, "ecs_cluster_region_0_id")),
		"CLUSTER_1":                clusterFromARN(terraform.Output(t, infraOpts, "ecs_cluster_region_1_id")),
		"ALB_ENDPOINT_0":           terraform.Output(t, appOpts, "region_0_alb_endpoint"),
		"ALB_ENDPOINT_1":           terraform.Output(t, appOpts, "region_1_alb_endpoint"),
		"ADMIN_USER":               "admin",
		"ADMIN_PASS":               terraform.Output(t, appOpts, "admin_user_password"),
		"AURORA_GLOBAL_CLUSTER_ID": globalClusterID,
		"AWS_PROFILE":              awsProfile,
	}
	for k, v := range env {
		if v == "" && k != "AWS_PROFILE" {
			t.Fatalf("ProcedureEnv: %s resolved to an empty value", k)
		}
	}
	return env
}
