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

// ParseAuroraWriterRegion reads the `GlobalClusters[0]` object returned by
// `aws rds describe-global-clusters` and returns the writer's region. It fails
// while a switchover or failover is in progress: a procedure that reports a
// writer move as complete must already have waited for it (#3572).
func ParseAuroraWriterRegion(raw []byte) (string, error) {
	var global struct {
		FailoverState *struct {
			Status string `json:"Status"`
		} `json:"FailoverState"`
		GlobalClusterMembers []struct {
			DBClusterArn string `json:"DBClusterArn"`
			IsWriter     bool   `json:"IsWriter"`
		} `json:"GlobalClusterMembers"`
	}
	if err := json.Unmarshal(raw, &global); err != nil {
		return "", fmt.Errorf("parse describe-global-clusters JSON: %w\n%s", err, raw)
	}
	if global.FailoverState != nil && global.FailoverState.Status != "" {
		return "", fmt.Errorf("Aurora switchover still in progress (%s)", global.FailoverState.Status)
	}
	for _, m := range global.GlobalClusterMembers {
		if m.IsWriter {
			region := regionFromDBClusterARN(m.DBClusterArn)
			if region == "" {
				return "", fmt.Errorf("could not extract region from writer ARN %q", m.DBClusterArn)
			}
			return region, nil
		}
	}
	return "", fmt.Errorf("no writer member in %s", raw)
}

// AuroraWriterRegion returns the AWS region (e.g. "eu-west-2") of the current
// writer cluster in the specified Aurora Global cluster. It reads once and
// does not retry, and fails the test if a switchover is still in progress.
func AuroraWriterRegion(t *testing.T, awsProfile, globalClusterID string) string {
	t.Helper()
	args := []string{
		"rds", "describe-global-clusters",
		"--global-cluster-identifier", globalClusterID,
		"--query", "GlobalClusters[0]",
		"--output", "json",
	}
	if awsProfile != "" {
		args = append(args, "--profile", awsProfile)
	}

	var stdout, stderr bytes.Buffer
	cmd := exec.Command("aws", args...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("aws rds describe-global-clusters failed: %v\n%s", err, stderr.String())
	}

	region, err := ParseAuroraWriterRegion(stdout.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	return region
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

// RunProcedureScript runs one of the procedure/*.sh scripts the way the README
// does: it first sources export_environment_prerequisites.sh, which reads the
// variables every procedure requires (clusters, ALB endpoints, admin
// password, ...) from the infra/ state in env["TF_DIR"]. The test's own
// environment is inherited, so the AWS CLI keeps its credentials. Fails the
// test on non-zero exit.
func RunProcedureScript(t *testing.T, scriptPath string, env map[string]string, extraArgs ...string) {
	t.Helper()

	if env["TF_DIR"] == "" {
		t.Fatal("RunProcedureScript needs TF_DIR, the infra/ state directory")
	}
	cmd := exec.Command("bash", append([]string{"-c",
		`. "$(dirname "$0")/export_environment_prerequisites.sh" >/dev/null && exec "$0" "$@"`,
		scriptPath}, extraArgs...)...)
	cmd.Env = os.Environ()
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

// ScaleDownRegion scales every ECS service of a cluster to zero tasks, the way
// a region outage leaves it, so a test can run failover.sh --keep-tasks.
func ScaleDownRegion(t *testing.T, awsProfile, region, cluster string) {
	t.Helper()

	aws := func(args ...string) string {
		args = append(args, "--region", region)
		if awsProfile != "" {
			args = append(args, "--profile", awsProfile)
		}
		out, err := exec.Command("aws", args...).CombinedOutput()
		if err != nil {
			t.Fatalf("aws %v failed: %v\n%s", args, err, out)
		}
		return string(out)
	}
	services := strings.Fields(aws("ecs", "list-services", "--cluster", cluster,
		"--query", "serviceArns[]", "--output", "text"))
	for _, service := range services {
		aws("ecs", "update-service", "--cluster", cluster, "--service", service,
			"--desired-count", "0", "--no-cli-pager")
	}
	// update-service returns before the tasks stop. Wait until they have, so the
	// brokers are really gone when failover.sh --keep-tasks removes the zone.
	// services-stable takes at most 10 services per call.
	for i := 0; i < len(services); i += 10 {
		aws(append([]string{"ecs", "wait", "services-stable", "--cluster", cluster, "--services"},
			services[i:min(i+10, len(services))]...)...)
	}
}

// RestoreAuroraWriterHome runs test/restore-aurora-writers.sh for one global
// cluster. It is safe in t.Cleanup: it waits for a switchover in progress,
// never calls t.Fatal, and reports a failure with t.Errorf so the state
// destroys registered before it still run.
func RestoreAuroraWriterHome(t *testing.T, scriptPath, awsProfile, region0, globalClusterID string) {
	t.Helper()
	cmd := exec.Command("bash", scriptPath, globalClusterID, "0")
	cmd.Env = append(os.Environ(), "REGION_0="+region0)
	if awsProfile != "" {
		cmd.Env = append(cmd.Env, "AWS_PROFILE="+awsProfile)
	}
	out, err := cmd.CombinedOutput()
	t.Logf("%s %s:\n%s", scriptPath, globalClusterID, out)
	if err != nil {
		t.Errorf("restoring the Aurora writer of %s: %v", globalClusterID, err)
	}
}
