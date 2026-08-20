package helpers

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
)

// TerraformOutputs is the subset of the terraform/clusters outputs the tests
// consume. Region-indexed outputs are maps keyed by the region slot as a
// string, which keeps adding a region from renaming anything.
type TerraformOutputs struct {
	RegionSlotCount   int
	ActiveRegionCount int
	AWSRegions        []string
	ShortNames        []string
	ZoneNames         []string
	ClusterNames      []string
	VPCCidrBlocks     []string
	ServiceCidrBlocks []string
	RdbmsURL          string
	RdbmsUsername     string
	RdbmsPassword     string
	AuroraGlobalID    string
}

type tfValue struct {
	Value json.RawMessage `json:"value"`
}

type tfRegion struct {
	Region    string `json:"region"`
	ShortName string `json:"short_name"`
}

// ReadTerraformOutputs runs `terraform output -json` once and decodes it.
// A single invocation is used on purpose: each `terraform output` call takes
// the state lock.
func ReadTerraformOutputs(t *testing.T, terraformDir string) TerraformOutputs {
	t.Helper()

	binary := GetEnv("TESTS_TF_BINARY_NAME", "terraform")
	cmd := exec.Command(binary, "-chdir="+terraformDir, "output", "-json")
	cmd.Env = os.Environ()

	raw, err := cmd.Output()
	if err != nil {
		t.Fatalf("terraform output failed in %s: %v", terraformDir, err)
	}

	var outputs map[string]tfValue
	if err := json.Unmarshal(raw, &outputs); err != nil {
		t.Fatalf("cannot decode terraform outputs: %v", err)
	}

	decode := func(key string, target any) {
		v, ok := outputs[key]
		if !ok {
			t.Fatalf("terraform output %q is missing; did the apply succeed?", key)
		}
		if err := json.Unmarshal(v.Value, target); err != nil {
			t.Fatalf("cannot decode terraform output %q: %v", key, err)
		}
	}

	decodeOptionalString := func(key string) string {
		v, ok := outputs[key]
		if !ok {
			return ""
		}
		var s string
		if err := json.Unmarshal(v.Value, &s); err != nil {
			return ""
		}
		return s
	}

	result := TerraformOutputs{}
	decode("region_slot_count", &result.RegionSlotCount)
	decode("active_region_count", &result.ActiveRegionCount)

	regions := map[string]tfRegion{}
	decode("regions", &regions)

	clusterNames := map[string]string{}
	decode("cluster_names", &clusterNames)

	vpcCidrs := map[string]string{}
	decode("vpc_cidr_blocks", &vpcCidrs)

	serviceCidrs := map[string]string{}
	decode("service_cidr_blocks", &serviceCidrs)

	// Every slot, not only the active ones: the Camunda zone list describes the
	// whole topology so an undeployed zone still has its replicas reserved.
	decode("zone_names", &result.ZoneNames)

	for i := 0; i < result.ActiveRegionCount; i++ {
		key := fmt.Sprint(i)
		region, ok := regions[key]
		if !ok {
			t.Fatalf("terraform output regions has no entry for slot %d", i)
		}
		result.AWSRegions = append(result.AWSRegions, region.Region)
		result.ShortNames = append(result.ShortNames, region.ShortName)
		result.ClusterNames = append(result.ClusterNames, clusterNames[key])
		result.VPCCidrBlocks = append(result.VPCCidrBlocks, vpcCidrs[key])
		result.ServiceCidrBlocks = append(result.ServiceCidrBlocks, serviceCidrs[key])
	}

	result.RdbmsURL = decodeOptionalString("camunda_rdbms_url")
	result.RdbmsUsername = decodeOptionalString("database_username")
	result.RdbmsPassword = decodeOptionalString("database_password")
	result.AuroraGlobalID = decodeOptionalString("database_global_cluster_id")

	return result
}

// UpdateKubeConfig registers one kubectl context per active region, aliased to
// the names the procedures expect.
func UpdateKubeConfig(t *testing.T, outputs TerraformOutputs, contexts []string) {
	t.Helper()

	if len(contexts) < len(outputs.ClusterNames) {
		t.Fatalf("got %d context aliases for %d clusters", len(contexts), len(outputs.ClusterNames))
	}

	for i, name := range outputs.ClusterNames {
		args := []string{
			"eks", "--region", outputs.AWSRegions[i],
			"update-kubeconfig", "--name", name,
			"--alias", contexts[i],
		}
		if profile := os.Getenv("AWS_PROFILE"); profile != "" {
			args = append(args, "--profile", profile)
		}

		cmd := exec.Command("aws", args...)
		out, err := cmd.CombinedOutput()
		t.Logf("aws %s\n%s", strings.Join(args, " "), string(out))
		if err != nil {
			t.Fatalf("cannot register the kubectl context for %s: %v", name, err)
		}
	}
}
