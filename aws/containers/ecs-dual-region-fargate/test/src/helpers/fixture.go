package helpers

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
)

// Fixture is the resolved configuration of one end-to-end run: the knobs the
// tests read back after building their ApplyOptions.
type Fixture struct {
	AWSProfile    string
	Region0       string
	Region1       string
	ClusterPrefix string
	RaftTimeout   time.Duration

	// Paths to the three Terraform module directories, and to procedure/.
	Paths        StatePaths
	ProcedureDir string
	// CallerDir is the test package directory, for helpers that resolve
	// fixtures relative to it.
	CallerDir string

	// Tags applied to every resource, so a leaked one is identifiable.
	Tags map[string]interface{}

	// Options to hand to ApplyAllThreeStates.
	Options ApplyOptions
}

// NewFixture resolves the standard environment overrides and assembles the
// ApplyOptions every end-to-end test needs.
//
// The four suites differ in exactly three things — the networking mode, the
// secondary storage, and a label — so those are the parameters; everything
// else was previously copy-pasted per file and had to be edited in lockstep.
//
// label seeds both the generated cluster prefix and the Purpose tag.
func NewFixture(t *testing.T, label, networkingMode, storageType string) Fixture {
	t.Helper()

	// Anchor on the caller's file so the module paths resolve regardless of
	// the working directory `go test` was invoked from.
	_, thisFile, _, _ := runtime.Caller(1)
	callerDir := filepath.Dir(thisFile)

	f := Fixture{
		AWSProfile:   envOrDefault("TEST_AWS_PROFILE", "infraex"),
		Region0:      envOrDefault("TEST_REGION_0", "eu-west-2"),
		Region1:      envOrDefault("TEST_REGION_1", "eu-west-3"),
		RaftTimeout:  time.Duration(envIntOrDefault(t, "TEST_RAFT_TIMEOUT_MIN", 30)) * time.Minute,
		Paths:        DefaultStatePaths(callerDir),
		ProcedureDir: filepath.Join(callerDir, "..", "..", "procedure"),
		CallerDir:    callerDir,
	}
	f.ClusterPrefix = envOrDefault("TEST_CLUSTER_PREFIX",
		fmt.Sprintf("e2e-%s-%s", label, strings.ToLower(random.UniqueId())))

	tags := map[string]interface{}{
		"Test":  "true",
		"RunID": f.ClusterPrefix,
		"Owner": "terratest",
		// The daily cleanup sweeps on state age, but the tag is what makes a
		// leaked resource identifiable in the console.
		"Purpose": fmt.Sprintf("ecs-dual-region-%s", label),
	}

	f.Tags = tags

	f.Options = ApplyOptions{
		VPCVars: map[string]interface{}{
			"cluster_name":       f.ClusterPrefix,
			"aws_profile":        f.AWSProfile,
			"region_0":           f.Region0,
			"region_1":           f.Region1,
			"networking_mode":    networkingMode,
			"single_nat_gateway": true,
			"default_tags":       tags,
		},
		InfraVars: map[string]interface{}{
			"cluster_name":           f.ClusterPrefix,
			"aws_profile":            f.AWSProfile,
			"region_0":               f.Region0,
			"region_1":               f.Region1,
			"secondary_storage_type": storageType,
			"s3_force_destroy":       true,
			"default_tags":           tags,
		},
		AppVars: map[string]interface{}{
			"aws_profile":  f.AWSProfile,
			"default_tags": tags,
		},
		BackendBucket:    envOrDefault("TEST_BACKEND_BUCKET", "tests-ra-aws-rosa-hcp-tf-state-eu-central-1"),
		BackendRegion:    envOrDefault("TEST_BACKEND_REGION", "eu-central-1"),
		BackendKeyPrefix: fmt.Sprintf("aws/containers/ecs-dual-region-fargate/%s/", f.ClusterPrefix),
	}
	return f
}

// Procedure returns the path of a procedure/*.sh script.
func (f Fixture) Procedure(name string) string {
	return filepath.Join(f.ProcedureDir, name)
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envIntOrDefault(t *testing.T, key string, fallback int) int {
	t.Helper()
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	var parsed int
	if _, err := fmt.Sscanf(v, "%d", &parsed); err != nil {
		t.Fatalf("%s must be an integer, got %q", key, v)
	}
	return parsed
}
