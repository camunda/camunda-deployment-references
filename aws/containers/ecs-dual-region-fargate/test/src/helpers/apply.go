// Package helpers contains shared utilities for ECS dual-region end-to-end tests.
//
// ApplyAllThreeStates wraps terraform init && apply for vpc/ → infra/ → app/ in
// sequence, returns the three terraform.Options so tests can read outputs, and
// registers each state's destroy with t.Cleanup (last-in first-out: app/,
// infra/, vpc/).
package helpers

import (
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// StatePaths resolves the three Terraform state directories relative to the
// test package location.
type StatePaths struct {
	VPC   string
	Infra string
	App   string
}

// DefaultStatePaths returns paths anchored at the standard layout:
//
//	aws/containers/ecs-dual-region-fargate/test/src/<helpers>
//	                                              └── terraform/{vpc,infra,app}/
//
// Tests in src/ call this with their package directory; the relative climb is
// two levels: src/ → test/ → ecs-dual-region-fargate/ → terraform/{vpc,infra,app}.
func DefaultStatePaths(packageDir string) StatePaths {
	root := filepath.Join(packageDir, "..", "..", "terraform")
	return StatePaths{
		VPC:   filepath.Join(root, "vpc"),
		Infra: filepath.Join(root, "infra"),
		App:   filepath.Join(root, "app"),
	}
}

// ApplyOptions bundles per-state variables and S3 backend configuration.
type ApplyOptions struct {
	VPCVars   map[string]interface{}
	InfraVars map[string]interface{}
	AppVars   map[string]interface{}

	// S3 backend — required. All three layers share the same bucket and region;
	// per-layer keys are derived as <BackendKeyPrefix>{vpc,infra,app}/terraform.tfstate.
	// BackendKeyPrefix must end with "/".
	BackendBucket    string
	BackendRegion    string
	BackendKeyPrefix string
}

func mergeMap(base, extra map[string]interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(base)+len(extra))
	for k, v := range base {
		out[k] = v
	}
	for k, v := range extra {
		out[k] = v
	}
	return out
}

// ApplyAllThreeStates applies vpc/ then infra/ then app/ in sequence. Returns
// the three terraform.Options so tests can read outputs (e.g. ALB endpoints
// from app/). Each state registers its destroy with t.Cleanup before it is
// applied, so a failure partway through still tears down what was created;
// cleanups run last-in first-out, which is app/, infra/, vpc/.
func ApplyAllThreeStates(t *testing.T, paths StatePaths, opts ApplyOptions) (vpcOpts, infraOpts, appOpts *terraform.Options) {
	t.Helper()

	backendVars := map[string]interface{}{
		"terraform_backend_bucket":     opts.BackendBucket,
		"terraform_backend_region":     opts.BackendRegion,
		"terraform_backend_key_prefix": opts.BackendKeyPrefix,
	}

	vpcBackend := map[string]interface{}{
		"bucket": opts.BackendBucket,
		"region": opts.BackendRegion,
		"key":    opts.BackendKeyPrefix + "vpc/terraform.tfstate",
	}
	infraBackend := map[string]interface{}{
		"bucket": opts.BackendBucket,
		"region": opts.BackendRegion,
		"key":    opts.BackendKeyPrefix + "infra/terraform.tfstate",
	}
	appBackend := map[string]interface{}{
		"bucket": opts.BackendBucket,
		"region": opts.BackendRegion,
		"key":    opts.BackendKeyPrefix + "app/terraform.tfstate",
	}

	vpcOpts = &terraform.Options{
		TerraformDir:       paths.VPC,
		Vars:               opts.VPCVars,
		BackendConfig:      vpcBackend,
		NoColor:            true,
		MaxRetries:         2,
		TimeBetweenRetries: 5,
	}
	destroyOnCleanup(t, "vpc", vpcOpts)
	t.Logf("Applying vpc/ state at %s", paths.VPC)
	terraform.InitAndApply(t, vpcOpts)

	infraOpts = &terraform.Options{
		TerraformDir:       paths.Infra,
		Vars:               mergeMap(opts.InfraVars, backendVars),
		BackendConfig:      infraBackend,
		NoColor:            true,
		MaxRetries:         2,
		TimeBetweenRetries: 5,
	}
	destroyOnCleanup(t, "infra", infraOpts)
	t.Logf("Applying infra/ state at %s", paths.Infra)
	terraform.InitAndApply(t, infraOpts)

	appOpts = &terraform.Options{
		TerraformDir:       paths.App,
		Vars:               mergeMap(opts.AppVars, backendVars),
		BackendConfig:      appBackend,
		NoColor:            true,
		MaxRetries:         2,
		TimeBetweenRetries: 5,
	}
	destroyOnCleanup(t, "app", appOpts)
	t.Logf("Applying app/ state at %s", paths.App)
	terraform.InitAndApply(t, appOpts)

	return vpcOpts, infraOpts, appOpts
}

func destroyOnCleanup(t *testing.T, name string, opts *terraform.Options) {
	t.Helper()
	t.Cleanup(func() {
		t.Logf("Destroying %s state at %s", name, opts.TerraformDir)
		if _, err := terraform.DestroyE(t, opts); err != nil {
			t.Errorf("destroy of %s failed: %v — manual cleanup may be required", name, err)
		}
	})
}

// SensitiveOutput reads a sensitive output without Terratest echoing its value
// into the test log, which CI publishes.
func SensitiveOutput(t *testing.T, opts *terraform.Options, name string) string {
	t.Helper()
	previous := opts.Logger
	opts.Logger = logger.Discard
	defer func() { opts.Logger = previous }()
	return terraform.Output(t, opts, name)
}
