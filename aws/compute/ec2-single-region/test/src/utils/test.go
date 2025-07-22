package utils

import (
	"fmt"
	"testing"

	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/gjson"
)

func APICheckCorrectCamundaVersion(t *testing.T, terraformOptions *terraform.Options, version string) {

	tfOutputs := terraform.OutputAll(t, terraformOptions)

	alb := tfOutputs["alb_endpoint"].(string)

	cmd := shell.Command{
		Command: "curl",
		Args:    []string{"-u", "demo:demo", fmt.Sprintf("%s/v2/topology", alb)},
	}
	output := shell.RunCommandAndGetStdOut(t, cmd)

	brokers := gjson.Get(output, "brokers").Array()
	clusterSize := gjson.Get(output, "clusterSize").Int()
	gatewayVersion := gjson.Get(output, "gatewayVersion").String()

	require.Equal(t, 3, len(brokers), "Expected 3 brokers, got %d", len(brokers))
	require.Equal(t, 3, int(clusterSize), "Expected static cluster size of 3, got %d", clusterSize)

	for _, broker := range brokers {
		// The 10.200 comes from the subnets configured in the terraform `variables.tf` as part of `cidr_blocks` for the `vpc.tf`.
		host := broker.Get("host").String()
		require.Contains(t, host, "10.200.", "Broker host should be in the private subnet")
	}

	if version != "" {
		require.Equal(t, version, gatewayVersion, "Expected gateway version %s, got %s", version, gatewayVersion)
	}
}

func APIDeployAndStartWorkflow(t *testing.T, terraformOptions *terraform.Options) {
	tfOutputs := terraform.OutputAll(t, terraformOptions)

	alb := tfOutputs["alb_endpoint"].(string)

	cmd := shell.Command{
		Command: "curl",
		Args:    []string{"-u", "demo:demo", "--form", "resources=@utils/single-task.bpmn", fmt.Sprintf("%s/v2/deployments", alb), "-H", "'Content-Type: multipart/form-data'", "-H", "'Accept: application/json'"},
	}
	output := shell.RunCommandAndGetStdOut(t, cmd)

	deployments := gjson.Get(output, "deployments").Array()
	resourceName := gjson.Get(output, "deployments.0.processDefinition.resourceName").String()
	tenantId := gjson.Get(output, "deployments.0.processDefinition.tenantId").String()
	processDefinitionKey := gjson.Get(output, "deployments.0.processDefinition.processDefinitionKey").Int()

	require.Equal(t, 1, len(deployments), "Expected 1 deployment, got %d", len(deployments))
	require.Equal(t, "single-task.bpmn", resourceName, "Expected 'single-task.bpmn', got %s", resourceName)
	require.Equal(t, "<default>", tenantId, "Expected '<default>', got %s", tenantId)

	cmd = shell.Command{
		Command: "curl",
		Args:    []string{"-u", "demo:demo", "-L", "-X", "POST", fmt.Sprintf("%s/v2/process-instances", alb), "-H", "Content-Type: application/json", "-H", "Accept: application/json", "--data-raw", fmt.Sprintf("{\"processDefinitionKey\":\"%d\"}", processDefinitionKey)},
	}
	shell.RunCommand(t, cmd)

	// TODO: in the future when other REST APIs are available we could check that those have been deployed / run etc.
	// atm still limited to v1 API

	cmd = shell.Command{
		Command: "curl",
		Args:    []string{"-u", "demo:demo", "-L", "-X", "POST", fmt.Sprintf("%s/v2/resources/%d/deletion", alb, processDefinitionKey)},
	}
	shell.RunCommand(t, cmd)
}

func ResetCamunda(t *testing.T, terraformOptions *terraform.Options, adminUsername string) {
	tfOutputs := terraform.OutputAll(t, terraformOptions)
	camundaIps := tfOutputs["camunda_ips"].([]interface{})
	bastionIp := tfOutputs["bastion_ip"].(string)
	openSearchConnection := tfOutputs["aws_opensearch_domain"].(string)

	for _, ip := range camundaIps {
		cmd := shell.Command{
			Command: "ssh",
			Args:    []string{"-J", fmt.Sprintf("%s@%s", adminUsername, bastionIp), fmt.Sprintf("%S@%s", adminUsername, ip), "sudo systemctl stop camunda"},
		}
		// Ignore error as the service might not be running
		shell.RunCommandE(t, cmd)

		cmd = shell.Command{
			Command: "ssh",
			Args:    []string{"-J", fmt.Sprintf("%s@%s", adminUsername, bastionIp), fmt.Sprintf("%s@%s", adminUsername, ip), "sudo systemctl stop connectors"},
		}
		// Ignore error as the service might not be running
		shell.RunCommandE(t, cmd)

		cmd = shell.Command{
			Command: "ssh",
			Args:    []string{"-J", fmt.Sprintf("%s@%s", adminUsername, bastionIp), fmt.Sprintf("%s@%s", adminUsername, ip), "sudo rm -rf /opt/camunda/*"},
		}
		shell.RunCommand(t, cmd)
	}

	cmd := shell.Command{
		Command: "ssh",
		Args:    []string{"-J", fmt.Sprintf("%s@%s", adminUsername, bastionIp), fmt.Sprintf("%s@%s", adminUsername, camundaIps[0]), fmt.Sprintf("curl -X DELETE %s/_all", openSearchConnection)},
	}
	output := shell.RunCommandAndGetStdOut(t, cmd)

	require.Contains(t, output, "{\"acknowledged\":true}", "Expected response to be acknowledged")
}
