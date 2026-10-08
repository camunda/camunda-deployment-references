// Aurora Global helpers — used by the failover/failback tests to observe the
// writer region and the global cluster's health. Nothing here mutates the
// cluster: procedure/failover.sh performs the promotion, and the tests assert
// on what it did.
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
)

type globalClusterMember struct {
	DBClusterArn string `json:"DBClusterArn"`
	// IsWriter, not IsClusterWriter. describe-global-clusters returns IsWriter
	// on GlobalClusterMembers; IsClusterWriter belongs to DBClusterMembers,
	// the instances inside one cluster. With the wrong tag this unmarshals
	// false for every member and AuroraWriterRegion fails with "no writer
	// member found" before the runbooks are ever exercised. The shell path
	// (procedure/failover.sh) always used .IsWriter, which is why the live run
	// promoted correctly while the Go tests could not have.
	IsWriter bool `json:"IsWriter"`
}

// globalCluster is the subset of describe-global-clusters the tests assert on.
type globalCluster struct {
	Status  string                `json:"Status"`
	Members []globalClusterMember `json:"GlobalClusterMembers"`
}

// auroraGlobal fetches the global cluster once. AuroraWriterRegion and
// AuroraGlobalClusterStatus used to issue a CLI call each, with a different
// --query against the same API call; one response carries both.
func auroraGlobal(t *testing.T, awsProfile, globalClusterID string) globalCluster {
	t.Helper()
	raw := awsJSON(t, awsProfile,
		"rds", "describe-global-clusters",
		"--global-cluster-identifier", globalClusterID,
		"--query", "GlobalClusters[0].{Status:Status,GlobalClusterMembers:GlobalClusterMembers}",
		"--output", "json",
	)
	var gc globalCluster
	if err := json.Unmarshal(raw, &gc); err != nil {
		t.Fatalf("parse describe-global-clusters JSON: %v\n%s", err, raw)
	}
	return gc
}

// AuroraWriterRegion returns the AWS region (e.g. "eu-west-2") of the current
// writer cluster in the specified Aurora Global cluster.
func AuroraWriterRegion(t *testing.T, awsProfile, globalClusterID string) string {
	t.Helper()
	for _, m := range auroraGlobal(t, awsProfile, globalClusterID).Members {
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

// AuroraGlobalClusterStatus returns the Status field of the global cluster.
func AuroraGlobalClusterStatus(t *testing.T, awsProfile, globalClusterID string) string {
	t.Helper()
	return auroraGlobal(t, awsProfile, globalClusterID).Status
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
