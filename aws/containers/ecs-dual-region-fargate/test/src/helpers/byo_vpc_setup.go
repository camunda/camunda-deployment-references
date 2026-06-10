// BYO-VPC fixture wrangler.
//
// SetupBYOVPCs applies the aws/test-fixtures/byo-vpcs/ Terraform config and
// returns its outputs as a map ready to merge into the ecs-dual-region-fargate
// vpc/ state's BYO tfvars. Caller is responsible for calling DestroyBYOVPCs
// (typically as a deferred cleanup AFTER the consuming states are destroyed).
package helpers

import (
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

// BYOVPCFixture wraps the test-fixture Terraform module.
type BYOVPCFixture struct {
	opts *terraform.Options
}

// SetupBYOVPCs locates aws/test-fixtures/byo-vpcs/ relative to the test
// directory, applies it with the supplied prefix and region pair, and returns
// a fixture handle. The handle's Outputs map is keyed by the same field
// names the consuming BYO tfvars expect (region_0_vpc_id, region_0_vpc_cidr,
// region_0_private_subnet_ids, ...).
func SetupBYOVPCs(t *testing.T, packageDir, prefix, awsProfile, region0, region1 string, tags map[string]interface{}) *BYOVPCFixture {
	t.Helper()

	// packageDir is test/src/helpers/ (one dir below test/src/).
	// Fixture path: ../../../../../test-fixtures/byo-vpcs/
	// climb: helpers -> src -> test -> ecs-dual-region-fargate -> containers -> aws -> repo
	// then descend: test-fixtures/byo-vpcs/
	fixtureDir := filepath.Join(packageDir, "..", "..", "..", "..", "..", "test-fixtures", "byo-vpcs")

	opts := &terraform.Options{
		TerraformDir: fixtureDir,
		Vars: map[string]interface{}{
			"prefix":      prefix,
			"aws_profile": awsProfile,
			"region_0":    region0,
			"region_1":    region1,
			"tags":        tags,
		},
		NoColor:            true,
		MaxRetries:         2,
		TimeBetweenRetries: 5,
	}

	t.Logf("Applying BYO-VPC fixture at %s", fixtureDir)
	terraform.InitAndApply(t, opts)

	return &BYOVPCFixture{opts: opts}
}

// ToTFVars returns the fixture outputs already shaped for the vpc/ state's
// BYO tfvars. Merge into your other vpc/ vars before passing to ApplyAllThreeStates.
func (f *BYOVPCFixture) ToTFVars(t *testing.T) map[string]interface{} {
	t.Helper()
	return map[string]interface{}{
		"region_0_vpc_id":                  terraform.Output(t, f.opts, "region_0_vpc_id"),
		"region_0_vpc_cidr":                terraform.Output(t, f.opts, "region_0_vpc_cidr"),
		"region_0_private_subnet_ids":      terraform.OutputList(t, f.opts, "region_0_private_subnet_ids"),
		"region_0_public_subnet_ids":       terraform.OutputList(t, f.opts, "region_0_public_subnet_ids"),
		"region_0_private_route_table_ids": terraform.OutputList(t, f.opts, "region_0_private_route_table_ids"),
		"region_1_vpc_id":                  terraform.Output(t, f.opts, "region_1_vpc_id"),
		"region_1_vpc_cidr":                terraform.Output(t, f.opts, "region_1_vpc_cidr"),
		"region_1_private_subnet_ids":      terraform.OutputList(t, f.opts, "region_1_private_subnet_ids"),
		"region_1_public_subnet_ids":       terraform.OutputList(t, f.opts, "region_1_public_subnet_ids"),
		"region_1_private_route_table_ids": terraform.OutputList(t, f.opts, "region_1_private_route_table_ids"),
	}
}

// DestroyBYOVPCs tears down the throwaway VPCs. Best-effort.
func (f *BYOVPCFixture) DestroyBYOVPCs(t *testing.T) {
	t.Helper()
	if f == nil || f.opts == nil {
		return
	}
	t.Logf("Destroying BYO-VPC fixture")
	if _, err := terraform.DestroyE(t, f.opts); err != nil {
		t.Errorf("BYO-VPC fixture destroy failed: %v — manual cleanup may be required", err)
	}
}
