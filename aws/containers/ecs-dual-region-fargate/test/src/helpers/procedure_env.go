package helpers

import (
	"bytes"
	"os/exec"
	"strings"
	"testing"
)

// ProcedureEnv returns the environment contract procedure/failover.sh and
// procedure/failback.sh hard-require via their `: "${VAR:?}"` guards.
//
// It does not re-derive those variables: it sources
// procedure/export_environment_prerequisites.sh — the script the README tells
// an operator to source before invoking the runbook — and reads back the
// environment it exported. A Go mirror of that contract would have to be kept
// in step by hand, and would fail in AWS, 40 minutes into a run, the first
// time the shell script exported something new.
//
// procedureDir is the repository's procedure/ directory; infraDir is the
// infra/ Terraform module whose outputs the script reads.
func ProcedureEnv(t *testing.T, procedureDir, infraDir, awsProfile string) map[string]string {
	t.Helper()

	// `env -0` rather than `env`: several exported values are multi-word, and
	// NUL termination is the only separator a value cannot contain.
	script := `set -a; . ./export_environment_prerequisites.sh >/dev/null 2>&1; env -0`

	cmd := exec.Command("bash", "-c", script)
	cmd.Dir = procedureDir
	cmd.Env = append(baseOSEnv(), "TF_DIR="+infraDir)
	if awsProfile != "" {
		cmd.Env = append(cmd.Env, "AWS_PROFILE="+awsProfile)
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("sourcing export_environment_prerequisites.sh failed: %v\n%s", err, stderr.String())
	}

	env := make(map[string]string)
	for _, pair := range strings.Split(stdout.String(), "\x00") {
		if k, v, ok := strings.Cut(pair, "="); ok {
			env[k] = v
		}
	}

	// Fail here, with a readable message, rather than inside a procedure
	// script forty minutes later. ADMIN_USER has a default in the script, so
	// it is not in this list.
	for _, required := range []string{
		"REGION_0", "REGION_1",
		"CLUSTER_0", "CLUSTER_1",
		"ALB_ENDPOINT_0", "ALB_ENDPOINT_1",
		"AURORA_GLOBAL_CLUSTER_ID", "AURORA_ENGINE",
		"ADMIN_PASS",
	} {
		if env[required] == "" {
			t.Fatalf("export_environment_prerequisites.sh did not export %s — the procedure scripts require it", required)
		}
	}
	return env
}
