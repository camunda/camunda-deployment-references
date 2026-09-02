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

// RunProcedureScript runs one of the procedure/*.sh scripts with the test's
// environment variables (REGION_0, REGION_1, CLUSTER_NAME, AWS_PROFILE,
// AURORA_GLOBAL_CLUSTER_ID exported). Fails the test on non-zero exit.
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
