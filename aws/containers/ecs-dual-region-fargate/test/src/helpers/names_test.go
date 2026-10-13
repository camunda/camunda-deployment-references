package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/stretchr/testify/require"
	"github.com/zclconf/go-cty/cty"
	"github.com/zclconf/go-cty/cty/function"
	"github.com/zclconf/go-cty/cty/function/stdlib"
)

func TestClusterPrefixPreservesRunIdentityThroughTerraformTruncation(t *testing.T) {
	t.Setenv("TEST_CLUSTER_PREFIX", "")
	seen := map[string]bool{}
	for _, runID := range []string{"38408214546", "38408214616", "38409214546"} {
		for _, suite := range []string{"tgw-rdbms", "os", "byo", "fo-planned", "fo-unplanned", "fb-noswitch", "fb-switch"} {
			t.Run(runID+"/"+suite, func(t *testing.T) {
				// Given: CI runs, including two IDs with identical last six digits.
				t.Setenv("TEST_RUN_ID", runID)
				// When
				prefix := ClusterPrefix(t, suite)
				// Then: both Terraform truncations retain the entire identity.
				require.LessOrEqual(t, len(prefix), 14)
				require.Regexp(t, `^e2e-[a-z]+-[a-z0-9]+$`, prefix)
				require.False(t, seen[prefix], "duplicate prefix %s", prefix)
				seen[prefix] = true
				for _, region := range []string{"-r0", "-r1"} {
					for _, suffix := range []string{"-alb", "-nlb-grpc", "-nlb-raft"} {
						require.LessOrEqual(t, len(prefix+region+suffix), 32)
					}
					targetPrefix := prefix + region + "-oc"
					require.True(t, strings.HasPrefix(targetPrefix[:min(17, len(targetPrefix))], prefix+region))
				}
				require.Contains(t, BackendKeyPrefix(prefix), "-run"+runID+"/")
				for suffix, limit := range map[string]int{
					"-r0-opensearch": 28, "-r0-oc-orchestration-task-role": 64,
					"-lt-load-generator-ecs-task-role": 64, "-r0-backup-abcdef": 63,
					"-r0-oc-bucket": 63, "-r0-camunda-db-0": 63,
					"-r0-oc.service.local": 63, "-r0-oc-sc": 1024,
					"-r0-oc-orchestration-cluster": 255, "-r0-resolver-outbound": 64,
				} {
					require.LessOrEqual(t, len(prefix+suffix), limit)
				}
				require.True(t, regexp.MustCompile(`^e2e-[a-z]+(-[a-z]+)*-[a-z0-9]+-global-db$`).MatchString(prefix+"-global-db"))
			})
		}
	}
}

func TestClusterPrefixMatchesWorkflowWriterCleanup(t *testing.T) {
	// Given
	workflow, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "..", "..", ".github", "workflows", "aws_ecs_dual_region_fargate_failover.yml"))
	require.NoError(t, err)
	start := strings.Index(string(workflow), "digits=0123456789abcdefghijklmnopqrstuvwxyz")
	require.GreaterOrEqual(t, start, 0)
	end := strings.Index(string(workflow)[start:], "./aws/containers/ecs-dual-region-fargate/test/restore-aurora-writers.sh")
	require.Greater(t, end, 0)
	for _, runID := range []string{"38408214546", "38408214616", "38409214546"} {
		t.Setenv("TEST_RUN_ID", runID)
		command := exec.Command("bash", "-c", string(workflow)[start:start+end]+`printf '%s' "$tag"`)
		command.Env = append(os.Environ(), "RUN_ID="+runID)
		// When
		tag, err := command.CombinedOutput()
		// Then
		require.NoError(t, err, string(tag))
		require.Equal(t, "e2e-p-"+string(tag), ClusterPrefix(t, "fo-planned"))
	}
}

func TestClusterPrefixKeepsLocalOverride(t *testing.T) {
	// Given
	t.Setenv("TEST_RUN_ID", "")
	t.Setenv("TEST_CLUSTER_PREFIX", "my-local-stack")
	// When / Then
	require.Equal(t, "my-local-stack", ClusterPrefix(t, "fo-planned"))
}

func TestClusterPrefixKeepsLocalRandomNaming(t *testing.T) {
	// Given
	t.Setenv("TEST_RUN_ID", "")
	t.Setenv("TEST_CLUSTER_PREFIX", "")
	// When / Then
	require.Regexp(t, `^e2e-fo-planned-[a-z0-9]{6}$`, ClusterPrefix(t, "fo-planned"))
}

func TestClusterPrefixSurvivesActualTerraformNameExpressions(t *testing.T) {
	// Given
	t.Setenv("TEST_RUN_ID", "38408214546")
	root := filepath.Join("..", "..", "..", "..", "..")
	prefix := ClusterPrefix(t, "fo-planned")
	seen := map[string]bool{}
	for _, path := range []string{
		"containers/ecs-dual-region-fargate/terraform/infra/lb.tf",
		"modules/ecs/fargate/orchestration-cluster/lb.tf",
		"modules/ecs/fargate/connectors/lb.tf",
	} {
		data, err := os.ReadFile(filepath.Join(root, path))
		require.NoError(t, err)
		file, diags := hclsyntax.ParseConfig(data, path, hcl.Pos{Line: 1, Column: 1})
		require.False(t, diags.HasErrors(), diags.Error())
		for _, region := range []string{"-r0", "-r1"} {
			ctx := &hcl.EvalContext{
				Variables: map[string]cty.Value{
					"local": cty.ObjectVal(map[string]cty.Value{"prefix_truncated": cty.StringVal(prefix)}),
					"var":   cty.ObjectVal(map[string]cty.Value{"prefix": cty.StringVal(prefix + region + "-oc")}),
				},
				Functions: map[string]function.Function{"substr": stdlib.SubstrFunc},
			}
			for _, block := range file.Body.(*hclsyntax.Body).Blocks {
				if block.Type != "resource" || (block.Labels[0] != "aws_lb" && block.Labels[0] != "aws_lb_target_group") {
					continue
				}
				if block.Labels[0] == "aws_lb" && region == "-r1" {
					continue
				}
				// When: evaluate the real resource name, not a copied expression.
				value, diags := block.Body.Attributes["name"].Expr.Value(ctx)
				require.False(t, diags.HasErrors(), diags.Error())
				name := value.AsString()
				// Then
				require.Contains(t, name, prefix)
				require.LessOrEqual(t, len(name), 32)
				require.False(t, seen[name], "duplicate AWS name %s", name)
				seen[name] = true
			}
		}
	}
}
