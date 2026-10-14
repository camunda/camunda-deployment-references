// Package helpers contains shared utilities for ECS dual-region end-to-end tests.
//
// ApplyAllThreeStates wraps terraform init && apply for vpc/ → infra/ → app/ in
// sequence, returns the three terraform.Options so tests can read outputs, and
// registers the destroy of each state with t.Cleanup before applying it.
package helpers

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/files"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// StatePaths contains the isolated stack and BYO fixture directories.
type StatePaths struct {
	VPC     string
	Infra   string
	App     string
	Fixture string
}

// RunTag names the resources of one test run: the last six digits of
// TEST_RUN_ID when CI sets it, which keeps names within AWS length limits, or a
// random ID locally.
func RunTag() string {
	if id := os.Getenv("TEST_RUN_ID"); len(id) >= 6 {
		return id[len(id)-6:]
	}
	return strings.ToLower(random.UniqueId())
}

// BackendKeyPrefix is the S3 key prefix of a test's states.
//
// The `tfstate-<id>/` segment is the layout aws-generic-terraform-cleanup
// groups by, so the daily cleanup and the workflows' cleanup step can reclaim
// the states of a run killed before its own t.Cleanup ran. Each state lives at
// `tfstate-<id>/<layer>/terraform.tfstate`, which the action reaches with
// `modules-order: app/terraform,infra/terraform,vpc/terraform,fixture/terraform`.
//
// In CI the group ends in `-run<TEST_RUN_ID>`, and the workflow targets
// `run<TEST_RUN_ID>/`. The action matches its target against the key field
// ($NF) of `aws s3 ls`, and this token cannot occur in another run's key.
func BackendKeyPrefix(clusterPrefix string) string {
	group := clusterPrefix
	if id := os.Getenv("TEST_RUN_ID"); id != "" {
		group += "-run" + id
	}
	return "aws/containers/ecs-dual-region-fargate/tfstate-" + group + "/"
}

// IsolatedStatePaths copies the Terraform code to a per-test temp directory
// and returns the three state directories inside it.
//
// The tests run in parallel. Sharing terraform/{vpc,infra,app} would make them
// share one .terraform directory, so each `terraform init` would repoint the
// others at its own backend key. The whole aws/ tree is copied because the
// states reference ../../../../modules.
//
// Tests in src/ call this with their package directory: src/ → test/ →
// ecs-dual-region-fargate/ → containers/ → aws/.
func IsolatedStatePaths(t *testing.T, packageDir string) StatePaths {
	t.Helper()

	awsRoot := filepath.Join(packageDir, "..", "..", "..", "..")
	dest := t.TempDir()
	copied, err := files.CopyTerraformFolderToDest(awsRoot, dest, "aws")
	if err != nil {
		t.Fatalf("copy the Terraform code: %v", err)
	}
	// asdf resolves the terraform version from .tool-versions in a parent
	// directory, which the temp copy is otherwise outside of.
	if err := files.CopyFile(filepath.Join(awsRoot, "..", ".tool-versions"), filepath.Join(dest, ".tool-versions")); err != nil {
		t.Fatalf("copy .tool-versions: %v", err)
	}
	root := filepath.Join(copied, "containers", "ecs-dual-region-fargate", "terraform")
	return StatePaths{
		VPC:     filepath.Join(root, "vpc"),
		Infra:   filepath.Join(root, "infra"),
		App:     filepath.Join(root, "app"),
		Fixture: filepath.Join(copied, "test-fixtures", "byo-vpcs"),
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
// from app/).
//
// Each state's destroy is registered with t.Cleanup before its apply, so a
// failed or partial apply is still torn down, in reverse order (t.Cleanup is
// LIFO). A deferred call taking the options as arguments would capture them
// before they are assigned, and destroy nothing.
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

// destroyOnCleanup destroys one state at the end of the test. The destroy is
// best effort: it reports a failure without stopping the remaining cleanups.
func destroyOnCleanup(t *testing.T, name string, opts *terraform.Options) {
	t.Helper()

	t.Cleanup(func() {
		t.Logf("Destroying %s state at %s", name, opts.TerraformDir)
		if _, err := terraform.DestroyE(t, opts); err != nil {
			t.Errorf("destroy of %s failed: %v — manual cleanup may be required", name, err)
		}
	})
}
