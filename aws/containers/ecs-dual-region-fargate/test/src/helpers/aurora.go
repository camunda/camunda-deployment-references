// Aurora Global helpers — used by the failover/failback tests to assert on
// writer-region changes and to reproduce the promotion AWS performs during a
// real region loss.
//
// Everything shells out to the AWS CLI through awsJSON (see ecs.go) rather
// than pulling in the SDK: the procedure scripts use the CLI, so the tests
// observe the system the same way an operator following the runbook does.
package helpers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type globalClusterMember struct {
	DBClusterArn string `json:"DBClusterArn"`
	IsWriter     bool   `json:"IsClusterWriter"`
}

// auroraGlobalMembers returns the global cluster's member list.
func auroraGlobalMembers(t *testing.T, awsProfile, globalClusterID string) []globalClusterMember {
	t.Helper()
	raw := awsJSON(t, awsProfile,
		"rds", "describe-global-clusters",
		"--global-cluster-identifier", globalClusterID,
		"--query", "GlobalClusters[0].GlobalClusterMembers",
		"--output", "json",
	)
	var members []globalClusterMember
	if err := json.Unmarshal(raw, &members); err != nil {
		t.Fatalf("parse describe-global-clusters JSON: %v\n%s", err, raw)
	}
	return members
}

// AuroraWriterRegion returns the AWS region (e.g. "eu-west-2") of the current
// writer cluster in the specified Aurora Global cluster.
func AuroraWriterRegion(t *testing.T, awsProfile, globalClusterID string) string {
	t.Helper()
	for _, m := range auroraGlobalMembers(t, awsProfile, globalClusterID) {
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

// auroraMemberARN returns the DB cluster ARN of the global cluster member
// that lives in the given region.
func auroraMemberARN(t *testing.T, awsProfile, globalClusterID, region string) string {
	t.Helper()
	for _, m := range auroraGlobalMembers(t, awsProfile, globalClusterID) {
		if regionFromDBClusterARN(m.DBClusterArn) == region {
			return m.DBClusterArn
		}
	}
	t.Fatalf("global cluster %s has no member in %s", globalClusterID, region)
	return "" // unreachable
}

// AuroraGlobalClusterStatus returns the Status field of the global cluster.
func AuroraGlobalClusterStatus(t *testing.T, awsProfile, globalClusterID string) string {
	t.Helper()
	raw := awsJSON(t, awsProfile,
		"rds", "describe-global-clusters",
		"--global-cluster-identifier", globalClusterID,
		"--query", "GlobalClusters[0].Status",
		"--output", "json",
	)
	var status string
	if err := json.Unmarshal(raw, &status); err != nil {
		t.Fatalf("parse describe-global-clusters status: %v\n%s", err, raw)
	}
	return status
}

// AuroraFailoverToRegion performs a planned Aurora Global failover, promoting
// the member in targetRegion to writer, and blocks until the promotion is
// visible.
//
// The failback tests need this because procedure/failover.sh deliberately
// leaves Aurora alone — in a real region loss AWS and the JDBC failover
// plugin move the writer, not the runbook. Without reproducing that move the
// --switch-writer variants become indistinguishable.
func AuroraFailoverToRegion(t *testing.T, awsProfile, globalClusterID, targetRegion string, timeout time.Duration) {
	t.Helper()

	targetARN := auroraMemberARN(t, awsProfile, globalClusterID, targetRegion)
	t.Logf("Promoting Aurora member %s to writer", targetARN)

	awsJSON(t, awsProfile,
		"rds", "failover-global-cluster",
		"--global-cluster-identifier", globalClusterID,
		"--target-db-cluster-identifier", targetARN,
		"--no-cli-pager",
		"--output", "json",
	)

	deadline := time.Now().Add(timeout)
	for {
		if AuroraWriterRegion(t, awsProfile, globalClusterID) == targetRegion {
			t.Logf("Aurora writer is now in %s", targetRegion)
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("Aurora writer did not move to %s within %s", targetRegion, timeout)
		}
		time.Sleep(15 * time.Second)
	}
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

// RunProcedureScript runs one of the procedure/*.sh scripts with env layered
// on top of the minimal host environment from baseOSEnv. Build env with
// ProcedureEnv, which sources the scripts' own prerequisites.
//
// Output is streamed as the script runs rather than buffered to the end: a
// failover takes minutes, and a silent log for that long is indistinguishable
// from a hang.
func RunProcedureScript(t *testing.T, scriptPath string, env map[string]string, extraArgs ...string) {
	t.Helper()

	cmd := exec.Command(scriptPath, extraArgs...)
	cmd.Env = append(cmd.Env, baseOSEnv()...)
	for k, v := range env {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	prefix := filepath.Base(scriptPath)
	cmd.Stdout = &logWriter{t: t, prefix: prefix}
	cmd.Stderr = &logWriter{t: t, prefix: prefix}

	t.Logf("Running %s %v", scriptPath, extraArgs)
	if err := cmd.Run(); err != nil {
		t.Fatalf("%s failed: %v (see the streamed output above)", scriptPath, err)
	}
	t.Logf("%s succeeded", scriptPath)
}

// baseOSEnv returns the subset of the host environment the procedure scripts
// need. PATH alone is not enough: the scripts call `aws --profile <name>`,
// which resolves the profile through HOME/AWS_CONFIG_FILE/
// AWS_SHARED_CREDENTIALS_FILE. Without those the CLI reports the profile as
// nonexistent and every script aborts on its first AWS call.
func baseOSEnv() []string {
	keys := []string{
		"PATH",
		"HOME",
		"AWS_CONFIG_FILE",
		"AWS_SHARED_CREDENTIALS_FILE",
		"AWS_PROFILE",
		"AWS_REGION",
		"AWS_DEFAULT_REGION",
		"AWS_ACCESS_KEY_ID",
		"AWS_SECRET_ACCESS_KEY",
		"AWS_SESSION_TOKEN",
		"TERM",
	}
	env := make([]string, 0, len(keys))
	for _, k := range keys {
		if v, ok := os.LookupEnv(k); ok {
			env = append(env, k+"="+v)
		}
	}
	return env
}

// logWriter forwards whole lines to t.Log as the child process emits them.
type logWriter struct {
	t      *testing.T
	prefix string
	buf    bytes.Buffer
}

func (w *logWriter) Write(p []byte) (int, error) {
	w.t.Helper()
	w.buf.Write(p)
	for {
		line, err := w.buf.ReadString('\n')
		if err != nil {
			// Partial line — put it back and wait for the rest.
			w.buf.WriteString(line)
			break
		}
		w.t.Logf("[%s] %s", w.prefix, strings.TrimRight(line, "\n"))
	}
	return len(p), nil
}
