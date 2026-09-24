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
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"
	"time"
)

// ProcedureDir returns the absolute path of the procedure directory.
//
// Resolved from this source file rather than from the working directory, which
// differs between the root test package and this one: `../procedure` is right
// for the first and points at a directory that does not exist for the second.
func ProcedureDir(t *testing.T) string {
	t.Helper()

	dir, err := procedureDir()
	if err != nil {
		t.Fatalf("cannot resolve the procedure directory: %v", err)
	}
	return dir
}

func procedureDir() (string, error) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		return "", errors.New("no caller information")
	}

	// <arch>/test/helpers/procedure.go -> <arch>/procedure
	return filepath.Abs(filepath.Join(filepath.Dir(thisFile), "..", "..", "procedure"))
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
	// ZoneReplicas holds the replicas of each partition per zone slot. Empty
	// means the default layout, which DefaultZoneReplicas keeps in step with
	// the procedure that owns it.
	ZoneReplicas   []int
	Namespace      string
	ReleaseName    string
	RdbmsURL       string
	RdbmsUsername  string
	RdbmsPassword  string
	AuroraGlobalID string
	Extra          map[string]string
}

// DefaultZoneReplicas mirrors the default layout of
// procedure/export_environment_prerequisites.sh: two replicas in each database
// zone and one in the remaining tie-breaker, so three slots give 2-2-1.
//
// The procedure owns the default; this is a copy, and TestZoneReplicasDefault
// MatchesTheProcedure fails if the two drift apart.
func DefaultZoneReplicas(slots int) []int {
	replicas := make([]int, slots)
	for i := range replicas {
		if i < 2 {
			replicas[i] = 2
		} else {
			replicas[i] = 1
		}
	}
	return replicas
}

// Vars renders the environment as a KEY=VALUE slice suitable for exec.Cmd.
func (e Env) Vars() []string {
	clusterSize := e.BrokersPerRegion * e.RegionSlots

	zoneReplicas := e.ZoneReplicas
	if len(zoneReplicas) == 0 {
		zoneReplicas = DefaultZoneReplicas(e.RegionSlots)
	}
	replicationFactor := 0
	fields := make([]string, len(zoneReplicas))
	for i, r := range zoneReplicas {
		replicationFactor += r
		fields[i] = fmt.Sprint(r)
	}

	vars := map[string]string{
		"CAMUNDA_REGION_SLOTS":       fmt.Sprint(e.RegionSlots),
		"CAMUNDA_ACTIVE_REGIONS":     fmt.Sprint(e.ActiveRegions),
		"CAMUNDA_BROKERS_PER_REGION": fmt.Sprint(e.BrokersPerRegion),
		"CAMUNDA_CLUSTER_SIZE":       fmt.Sprint(clusterSize),
		"CAMUNDA_PARTITION_COUNT":    fmt.Sprint(clusterSize),
		"CAMUNDA_REPLICATION_FACTOR": fmt.Sprint(replicationFactor),
		"CAMUNDA_ZONE_REPLICAS":      strings.Join(fields, " "),
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
		"CAMUNDA_HELM_CHART_GIT_REF": ChartGitRef(),
		// Forwarded as-is, with no fallback. The chart's demo/demo admin login
		// caused INC-5340, so an unset credential has to surface as the
		// procedure refusing to run; camunda::_basic_auth does exactly that.
		"CAMUNDA_BASIC_AUTH_USER":     os.Getenv("CAMUNDA_BASIC_AUTH_USER"),
		"CAMUNDA_BASIC_AUTH_PASSWORD": os.Getenv("CAMUNDA_BASIC_AUTH_PASSWORD"),
		// Optional Helm overlay, e.g. the CI credentials values file. Empty
		// outside CI, where install-chart.sh simply skips it.
		"CAMUNDA_EXTRA_VALUES": GetEnv("CAMUNDA_EXTRA_VALUES", ""),
	}
	for k, v := range e.Extra {
		vars[k] = v
	}

	out := make([]string, 0, len(os.Environ())+len(vars))
	for _, entry := range os.Environ() {
		// Drop the inherited copy of every key the harness sets: which one wins
		// otherwise depends on the developer's shell and on the reader's libc.
		if key, _, found := strings.Cut(entry, "="); found {
			if _, overridden := vars[key]; overridden {
				continue
			}
		}
		out = append(out, entry)
	}
	for k, v := range vars {
		out = append(out, k+"="+v)
	}
	return out
}

// RunProcedure executes a procedure script and fails the test on a non-zero
// exit status. Output is buffered and written to the test log once the script
// ends, so a CI failure carries the script output rather than only its exit
// code. Nothing appears while it runs: `go test` interleaves nothing anyway
// until the test finishes, and a run that hangs is diagnosed from the timeout
// dump below rather than from a live tail.
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
		// Reaped, and the goroutine given a moment to flush what the script had
		// already written: killing without waiting leaves a zombie until the test
		// binary exits, and drops the tail of the output that explains the hang.
		select {
		case <-done:
		case <-time.After(5 * time.Second):
		}
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

var chartGitRefPattern = regexp.MustCompile(`(?m)^export CAMUNDA_HELM_CHART_GIT_REF="\$\{CAMUNDA_HELM_CHART_GIT_REF:-([^}"]+)\}"`)

// ChartGitRef returns the Helm chart pin that the procedures use.
//
// The value is read from procedure/export_environment_prerequisites.sh instead
// of being repeated here. That script is what a user sources, so it owns the
// pin; the tests run one procedure at a time and never source it, which is why
// the value has to be read rather than inherited. Repeating the commit would
// let the harness and the documented procedure drift onto different charts
// without anything failing. An explicit environment override still wins.
func ChartGitRef() string {
	if ref, ok := os.LookupEnv("CAMUNDA_HELM_CHART_GIT_REF"); ok && ref != "" {
		return ref
	}

	dir, err := procedureDir()
	if err != nil {
		panic("cannot resolve the procedure directory: " + err.Error())
	}

	path := filepath.Join(dir, "export_environment_prerequisites.sh")
	content, err := os.ReadFile(path)
	if err != nil {
		panic("cannot read the Helm chart pin: " + err.Error())
	}

	match := chartGitRefPattern.FindSubmatch(content)
	if match == nil {
		panic("no CAMUNDA_HELM_CHART_GIT_REF default found in " + path)
	}
	return string(match[1])
}
