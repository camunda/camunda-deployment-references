// Package helpers provides thin wrappers used by the multi-region RDBMS
// integration tests.
//
// The tests deliberately drive the shell procedures under ../../procedure
// instead of reimplementing them in Go. That keeps a single source of truth:
// what CI validates is exactly what a user copy-pastes from the documentation,
// and a bug in a procedure fails the test instead of hiding behind a Go
// reimplementation of the same logic.
package helpers

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// ProcedureDir returns the absolute path of the procedure directory.
func ProcedureDir(t *testing.T) string {
	t.Helper()

	dir, err := filepath.Abs(filepath.Join("..", "procedure"))
	if err != nil {
		t.Fatalf("cannot resolve the procedure directory: %v", err)
	}
	return dir
}

// Env is the environment contract shared by every procedure.
type Env struct {
	RegionSlots          int
	ActiveRegions        int
	BrokersPerRegion     int
	ClusterContexts      []string
	AWSRegions           []string
	SubmarinerClusters   []string
	ZoneNames            []string
	ClusterNames         []string
	VPCCidrBlocks        []string
	ServiceCidrBlocks    []string
	SubmarinerBrokerSlot int
	Namespace            string
	ReleaseName          string
	RdbmsURL             string
	RdbmsUsername        string
	RdbmsPassword        string
	AuroraGlobalID       string
	Extra                map[string]string
}

// Vars renders the environment as a KEY=VALUE slice suitable for exec.Cmd.
func (e Env) Vars() []string {
	clusterSize := e.BrokersPerRegion * e.RegionSlots

	vars := map[string]string{
		"CAMUNDA_REGION_SLOTS":       fmt.Sprint(e.RegionSlots),
		"CAMUNDA_ACTIVE_REGIONS":     fmt.Sprint(e.ActiveRegions),
		"CAMUNDA_BROKERS_PER_REGION": fmt.Sprint(e.BrokersPerRegion),
		"CAMUNDA_CLUSTER_SIZE":       fmt.Sprint(clusterSize),
		"CAMUNDA_PARTITION_COUNT":    fmt.Sprint(clusterSize),
		"CAMUNDA_REPLICATION_FACTOR": fmt.Sprint(e.RegionSlots),
		"CLUSTER_CONTEXTS":           strings.Join(e.ClusterContexts, " "),
		"AWS_REGIONS":                strings.Join(e.AWSRegions, " "),
		"SUBMARINER_CLUSTER_IDS":     strings.Join(e.SubmarinerClusters, " "),
		"CAMUNDA_ZONE_NAMES":         strings.Join(e.ZoneNames, " "),
		"SUBMARINER_BROKER_SLOT":     fmt.Sprint(e.SubmarinerBrokerSlot),
		"EKS_CLUSTER_NAMES":          strings.Join(e.ClusterNames, " "),
		"REGION_VPC_CIDRS":           strings.Join(e.VPCCidrBlocks, " "),
		"REGION_SERVICE_CIDRS":       strings.Join(e.ServiceCidrBlocks, " "),
		"CAMUNDA_NAMESPACE":          e.Namespace,
		"CAMUNDA_RELEASE_NAME":       e.ReleaseName,
		"CAMUNDA_RDBMS_URL":          e.RdbmsURL,
		"CAMUNDA_RDBMS_USERNAME":     e.RdbmsUsername,
		"CAMUNDA_RDBMS_PASSWORD":     e.RdbmsPassword,
		"AURORA_GLOBAL_CLUSTER_ID":   e.AuroraGlobalID,
		// The chart is built from source, and zone awareness is not in a
		// released chart yet. The harness builds this environment itself
		// instead of sourcing export_environment_prerequisites.sh, so a ref set
		// only there never reaches CI -- which is exactly what happened: the
		// run built the released pin, silently ignored `mode: zoned`, and fell
		// back to legacy numbering with every region numbering its brokers
		// identically.
		"CAMUNDA_HELM_CHART_GIT_REF":  GetEnv("CAMUNDA_HELM_CHART_GIT_REF", "feat/zoned-mode-node-id"),
		"CAMUNDA_BASIC_AUTH_USER":     GetEnv("CAMUNDA_BASIC_AUTH_USER", "demo"),
		"CAMUNDA_BASIC_AUTH_PASSWORD": GetEnv("CAMUNDA_BASIC_AUTH_PASSWORD", "demo"),
		// Optional Helm overlay, e.g. the CI credentials values file. Empty
		// outside CI, where install-chart.sh simply skips it.
		"CAMUNDA_EXTRA_VALUES": GetEnv("CAMUNDA_EXTRA_VALUES", ""),
	}
	for k, v := range e.Extra {
		vars[k] = v
	}

	out := os.Environ()
	for k, v := range vars {
		out = append(out, k+"="+v)
	}
	return out
}

// RunProcedure executes a procedure script and fails the test on a non-zero
// exit status. Output is streamed to the test log so that a CI failure carries
// the script output rather than only its exit code.
func RunProcedure(t *testing.T, env Env, timeout time.Duration, script string, args ...string) string {
	t.Helper()

	dir := ProcedureDir(t)
	path := filepath.Join(dir, script)

	if _, err := os.Stat(path); err != nil {
		t.Fatalf("procedure %s does not exist: %v", script, err)
	}

	cmd := exec.Command("bash", append([]string{path}, args...)...)
	cmd.Dir = dir
	cmd.Env = env.Vars()

	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf

	done := make(chan error, 1)
	start := time.Now()
	if err := cmd.Start(); err != nil {
		t.Fatalf("cannot start %s: %v", script, err)
	}
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		t.Logf("=== %s (%s) ===\n%s", script, time.Since(start).Round(time.Second), buf.String())
		if err != nil {
			t.Fatalf("%s failed: %v", script, err)
		}
	case <-time.After(timeout):
		_ = cmd.Process.Kill()
		t.Logf("=== %s (timed out) ===\n%s", script, buf.String())
		t.Fatalf("%s did not finish within %s", script, timeout)
	}

	return buf.String()
}

// RunProcedureAllowFailure behaves like RunProcedure but reports the error
// instead of failing, for diagnostics wired into a cleanup path.
//
// The timeout is enforced: these are best-effort diagnostic scripts, and a
// stuck kubectl call inside one would otherwise hang the whole run long after
// the failure it was meant to explain.
func RunProcedureAllowFailure(t *testing.T, env Env, timeout time.Duration, script string, args ...string) {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	dir := ProcedureDir(t)
	cmd := exec.CommandContext(ctx, "bash", append([]string{filepath.Join(dir, script)}, args...)...)
	cmd.Dir = dir
	cmd.Env = env.Vars()

	out, err := cmd.CombinedOutput()
	t.Logf("=== %s (best effort) ===\n%s", script, string(out))

	switch {
	case ctx.Err() == context.DeadlineExceeded:
		t.Logf("%s exceeded its %s budget and was killed (ignored)", script, timeout)
	case err != nil:
		t.Logf("%s returned %v (ignored)", script, err)
	}
}

// GetEnv reads an environment variable with a fallback.
func GetEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
