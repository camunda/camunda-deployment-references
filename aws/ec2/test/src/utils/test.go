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

func CheckCorrectCamundaVersion(t *testing.T, terraformOptions *terraform.Options, version string) {

	tfOutputs := terraform.OutputAll(t, terraformOptions)

	alb := tfOutputs["alb_endpoint"].(string)

	cmd := shell.Command{
		Command: "bash",
		Args:    []string{"-c", fmt.Sprintf("curl -f --request POST '%s/api/login?username=demo&password=demo' --cookie-jar cookie.txt", alb)},
	}
	shell.RunCommand(t, cmd)

	cmd = shell.Command{
		Command: "bash",
		Args:    []string{"-c", fmt.Sprintf("curl -f --cookie cookie.txt %s/v2/topology", alb)},
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
		require.Contains(t, broker.Host, "10.200.", "Broker host should be in the private subnet")
	}

	if version != "" {
		require.Equal(t, version, cluster.GatewayVersion, "Expected gateway version %s, got %s", version, cluster.GatewayVersion)
	}
}

func ResetCamunda(t *testing.T, terraformOptions *terraform.Options) {
	tfOutputs := terraform.OutputAll(t, terraformOptions)
	camundaIps := tfOutputs["camunda_ips"].([]interface{})
	bastionIp := tfOutputs["bastion_ip"].(string)
	openSearchConnection := tfOutputs["aws_opensearch_domain"].(string)

	for _, ip := range camundaIps {
		cmd := shell.Command{
			Command: "bash",
			Args:    []string{"-c", fmt.Sprintf("ssh -J admin@%s admin@%s \"sudo systemctl stop camunda\"", bastionIp, ip)},
		}
		shell.RunCommand(t, cmd)

		cmd = shell.Command{
			Command: "bash",
			Args:    []string{"-c", fmt.Sprintf("ssh -J admin@%s admin@%s \"sudo systemctl stop connectors\"", bastionIp, ip)},
		}
		shell.RunCommand(t, cmd)

		cmd = shell.Command{
			Command: "bash",
			Args:    []string{"-c", fmt.Sprintf("ssh -J admin@%s admin@%s \"sudo rm -rf /opt/camunda/*\"", bastionIp, ip)},
		}
		shell.RunCommand(t, cmd)
	}

	cmd := shell.Command{
		Command: "bash",
		Args:    []string{"-c", fmt.Sprintf("ssh -J admin@%s admin@%s \"curl -X DELETE %s/_all\"", bastionIp, camundaIps[0], openSearchConnection)},
	}
	output := shell.RunCommandAndGetStdOut(t, cmd)

	require.Contains(t, output, "{\"acknowledged\":true}", "Expected response to be acknowledged")
}
