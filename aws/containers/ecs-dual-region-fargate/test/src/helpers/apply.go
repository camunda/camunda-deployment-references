// Package helpers contains shared utilities for ECS dual-region end-to-end tests.
//
// ApplyAllThreeStates wraps terraform init && apply for vpc/ → infra/ → app/ in
// sequence, returns the three terraform.Options so tests can read outputs, and
// is paired with DestroyAllThreeStates for orderly teardown in reverse order.
package helpers

import (
	"path/filepath"
	"testing"

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
	root := filepath.Join(packageDir, "..", "..", "..", "terraform")
	return StatePaths{
		VPC:   filepath.Join(root, "vpc"),
		Infra: filepath.Join(root, "infra"),
		App:   filepath.Join(root, "app"),
	}
}

// ApplyOptions bundles per-state variables. All states share aws_profile and
// region pair; per-state vars cover the toggles each layer needs.
type ApplyOptions struct {
	VPCVars   map[string]interface{}
	InfraVars map[string]interface{}
	AppVars   map[string]interface{}

	// BackendConfig is applied to every state's terraform init -backend-config=
	// flags. Use this for S3 backend or the local-backend override path.
	BackendConfig map[string]interface{}
}

// ApplyAllThreeStates applies vpc/ then infra/ then app/ in sequence. Returns
// the three terraform.Options so tests can read outputs (e.g. ALB endpoints
// from app/). Caller MUST `defer DestroyAllThreeStates(t, opts)` to clean up.
func ApplyAllThreeStates(t *testing.T, paths StatePaths, opts ApplyOptions) (vpcOpts, infraOpts, appOpts *terraform.Options) {
	t.Helper()

	vpcOpts = &terraform.Options{
		TerraformDir:       paths.VPC,
		Vars:               opts.VPCVars,
		BackendConfig:      opts.BackendConfig,
		NoColor:            true,
		MaxRetries:         2,
		TimeBetweenRetries: 5,
	}
	t.Logf("Applying vpc/ state at %s", paths.VPC)
	terraform.InitAndApply(t, vpcOpts)

	infraOpts = &terraform.Options{
		TerraformDir:       paths.Infra,
		Vars:               opts.InfraVars,
		BackendConfig:      opts.BackendConfig,
		NoColor:            true,
		MaxRetries:         2,
		TimeBetweenRetries: 5,
	}
	t.Logf("Applying infra/ state at %s", paths.Infra)
	terraform.InitAndApply(t, infraOpts)

	appOpts = &terraform.Options{
		TerraformDir:       paths.App,
		Vars:               opts.AppVars,
		BackendConfig:      opts.BackendConfig,
		NoColor:            true,
		MaxRetries:         2,
		TimeBetweenRetries: 5,
	}
	t.Logf("Applying app/ state at %s", paths.App)
	terraform.InitAndApply(t, appOpts)

	return vpcOpts, infraOpts, appOpts
}

// DestroyAllThreeStates destroys app/ then infra/ then vpc/ in reverse-apply
// order. Safe to call as a defer even if Apply failed partway — each Destroy
// is best-effort and logs without failing the test (the deferred destroy is
// cleanup, not assertion).
func DestroyAllThreeStates(t *testing.T, appOpts, infraOpts, vpcOpts *terraform.Options) {
	t.Helper()

	for _, step := range []struct {
		name string
		opts *terraform.Options
	}{
		{"app", appOpts},
		{"infra", infraOpts},
		{"vpc", vpcOpts},
	} {
		if step.opts == nil {
			t.Logf("Skipping %s destroy (state was not applied)", step.name)
			continue
		}
		t.Logf("Destroying %s state at %s", step.name, step.opts.TerraformDir)
		if _, err := terraform.DestroyE(t, step.opts); err != nil {
			t.Errorf("destroy of %s failed: %v — manual cleanup may be required", step.name, err)
		}
	}
}
