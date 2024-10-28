package utils

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/camunda/camunda-deployment-references/aws/ec2/camunda"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

func OverwriteTerraformLifecycle(filePath string) {
	content, err := os.ReadFile(filePath)
	if err != nil {
		fmt.Println("Error reading file:", err)
		return
	}

	fileContent := string(content)
	updatedContent := strings.Replace(fileContent, "prevent_destroy       = true", "prevent_destroy       = false", 1)

	// Write the updated content back to the file
	err = os.WriteFile(filePath, []byte(updatedContent), 0644)
	if err != nil {
		fmt.Println("Error writing to file:", err)
		return
	}
}

func APICheckCorrectCamundaVersion(t *testing.T, terraformOptions *terraform.Options, version string) {

	tfOutputs := terraform.OutputAll(t, terraformOptions)

	alb := tfOutputs["alb_endpoint"].(string)

	// Using the cookie of Operate for the v2 API is a workaround as v2 API is secured in single jar, even though there's no identity yet
	// TODO: Remove workaround when proper identity is in place
	cmd := shell.Command{
		Command: "curl",
		Args:    []string{"-f", "--request", "POST", fmt.Sprintf("%s/api/login?username=demo&password=demo", alb), "--cookie-jar", "cookie.txt"},
	}
	shell.RunCommand(t, cmd)

	cmd = shell.Command{
		Command: "curl",
		Args:    []string{"-f", "--cookie", "cookie.txt", fmt.Sprintf("%s/v2/topology", alb)},
	}
	output := shell.RunCommandAndGetStdOut(t, cmd)

	var cluster camunda.Cluster
	err := json.Unmarshal([]byte(output), &cluster)
	if err != nil {
		fmt.Println("Error:", err)
	}

	require.Equal(t, 3, len(cluster.Brokers), "Expected 3 brokers, got %d", len(cluster.Brokers))
	require.Equal(t, 3, cluster.ClusterSize, "Expected static cluster size of 3, got %d", cluster.ClusterSize)

	for _, broker := range cluster.Brokers {
		// The 10.200 comes from the subnets configured in the terraform `variables.tf` as part of `cidr_blocks` for the `vpc.tf`.
		require.Contains(t, broker.Host, "10.200.", "Broker host should be in the private subnet")
	}

	if version != "" {
		require.Equal(t, version, cluster.GatewayVersion, "Expected gateway version %s, got %s", version, cluster.GatewayVersion)
	}
}

func APIDeployAndStartWorkflow(t *testing.T, terraformOptions *terraform.Options) {
	tfOutputs := terraform.OutputAll(t, terraformOptions)

	alb := tfOutputs["alb_endpoint"].(string)

	cmd := shell.Command{
		Command: "curl",
		Args:    []string{"-f", "--request", "POST", fmt.Sprintf("%s/api/login?username=demo&password=demo", alb), "--cookie-jar", "cookie.txt"},
	}
	shell.RunCommand(t, cmd)

	cmd = shell.Command{
		Command: "curl",
		Args:    []string{"-f", "--cookie", "cookie.txt", "--form", "resources=@utils/single-task.bpmn", fmt.Sprintf("%s/v2/deployments", alb), "-H", "'Content-Type: multipart/form-data'", "-H", "'Accept: application/json'"},
	}
	output := shell.RunCommandAndGetStdOut(t, cmd)

	var deploymentInfo camunda.DeploymentInfo
	err := json.Unmarshal([]byte(output), &deploymentInfo)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	require.Equal(t, 1, len(deploymentInfo.Deployments), "Expected 1 deployment, got %d", len(deploymentInfo.Deployments))
	require.Equal(t, "single-task.bpmn", deploymentInfo.Deployments[0].ProcessDefinition.ResourceName, "Expected 'single-task.bpmn', got %s", deploymentInfo.Deployments[0].ProcessDefinition.ResourceName)
	require.Equal(t, "<default>", deploymentInfo.Deployments[0].ProcessDefinition.TenantId, "Expected '<default>', got %s", deploymentInfo.Deployments[0].ProcessDefinition.TenantId)

	cmd = shell.Command{
		Command: "curl",
		Args:    []string{"-f", "--cookie", "cookie.txt", "-L", "-X", "POST", fmt.Sprintf("%s/v2/process-instances", alb), "-H", "Content-Type: application/json", "-H", "Accept: application/json", "--data-raw", fmt.Sprintf("{\"processDefinitionKey\":\"%d\"}", deploymentInfo.Deployments[0].ProcessDefinition.ProcessDefinitionKey)},
	}
	shell.RunCommand(t, cmd)

	// TODO: in the future when other REST APIs are available we could check that those have been deployed / run etc.
	// atm still limited to v1 API

	cmd = shell.Command{
		Command: "curl",
		Args:    []string{"-f", "--cookie", "cookie.txt", "-L", "-X", "POST", fmt.Sprintf("%s/v2/resources/%d/deletion", alb, deploymentInfo.Deployments[0].ProcessDefinition.ProcessDefinitionKey)},
	}
	shell.RunCommand(t, cmd)
}

func ResetCamunda(t *testing.T, terraformOptions *terraform.Options) {
	tfOutputs := terraform.OutputAll(t, terraformOptions)
	camundaIps := tfOutputs["camunda_ips"].([]interface{})
	bastionIp := tfOutputs["bastion_ip"].(string)
	openSearchConnection := tfOutputs["aws_opensearch_domain"].(string)

	for _, ip := range camundaIps {
		cmd := shell.Command{
			Command: "ssh",
			Args:    []string{"-J", fmt.Sprintf("admin@%s", bastionIp), fmt.Sprintf("admin@%s", ip), "sudo systemctl stop camunda"},
		}
		// Ignore error as the service might not be running
		shell.RunCommandE(t, cmd)

		cmd = shell.Command{
			Command: "ssh",
			Args:    []string{"-J", fmt.Sprintf("admin@%s", bastionIp), fmt.Sprintf("admin@%s", ip), "sudo systemctl stop connectors"},
		}
		// Ignore error as the service might not be running
		shell.RunCommandE(t, cmd)

		cmd = shell.Command{
			Command: "ssh",
			Args:    []string{"-J", fmt.Sprintf("admin@%s", bastionIp), fmt.Sprintf("admin@%s", ip), "sudo rm -rf /opt/camunda/*"},
		}
		shell.RunCommand(t, cmd)
	}

	cmd := shell.Command{
		Command: "ssh",
		Args:    []string{"-J", fmt.Sprintf("admin@%s", bastionIp), fmt.Sprintf("admin@%s", camundaIps[0]), fmt.Sprintf("curl -X DELETE %s/_all", openSearchConnection)},
	}
	output := shell.RunCommandAndGetStdOut(t, cmd)

	require.Contains(t, output, "{\"acknowledged\":true}", "Expected response to be acknowledged")
}
