package test

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/user"
	"path/filepath"
	"testing"
	"time"

	"github.com/camunda/camunda-deployment-references/aws/ec2/utils"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// Topology
type Partition struct {
	PartitionId int    `json:"partitionId"`
	Role        string `json:"role"`
	Health      string `json:"health"`
}

type Broker struct {
	NodeId     int         `json:"nodeId"`
	Host       string      `json:"host"`
	Port       int         `json:"port"`
	Partitions []Partition `json:"partitions"`
	Version    string      `json:"version"`
}

type Cluster struct {
	Brokers           []Broker `json:"brokers"`
	ClusterSize       int      `json:"clusterSize"`
	PartitionsCount   int      `json:"partitionsCount"`
	ReplicationFactor int      `json:"replicationFactor"`
	GatewayVersion    string   `json:"gatewayVersion"`
}

// Deployment
type ProcessDefinition struct {
	ProcessDefinitionId      string `json:"processDefinitionId"`
	ProcessDefinitionVersion int    `json:"processDefinitionVersion"`
	ProcessDefinitionKey     int64  `json:"processDefinitionKey"`
	ResourceName             string `json:"resourceName"`
	TenantId                 string `json:"tenantId"`
}

type Deployment struct {
	ProcessDefinition ProcessDefinition `json:"processDefinition"`
}

type DeploymentInfo struct {
	DeploymentKey int64        `json:"deploymentKey"`
	Deployments   []Deployment `json:"deployments"`
	TenantId      string       `json:"tenantId"`
}

const (
	terraformDir = "../../terraform"
	privKeyName  = "ec2-jar-priv"
)

var (
	tfBinary = utils.GetEnv("TERRAFORM_BINARY", "terraform")
	tfVars   = map[string]interface{}{
		"prefix":                utils.GetEnv("TF_PREFIX", "ec2-jar-test"),
		"generate_ssh_key_pair": true,
	}
)

// func TestSetup(t *testing.T) {
// 	t.Log("Test setup")

// 	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
// 		TerraformBinary: tfBinary,
// 		TerraformDir:    terraformDir,
// 		Vars:            tfVars,
// 		NoColor:         true,
// 	})

// 	terraform.InitAndApply(t, terraformOptions)
// }

func TestConnectivity(t *testing.T) {
	t.Log("Test connectivity to EC2 instances")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformBinary: tfBinary,
		TerraformDir:    terraformDir,
		Vars:            tfVars,
		NoColor:         true,
		Logger:          logger.Discard, // disable logger due to sensitive data but will still log on error
	})

	// expected values
	expectedOutputLength := 8
	expectedEc2Instances := 3

	stringOutputs := [...]string{"aws_ami", "alb_endpoint", "nlb_endpoint", "private_key", "public_key", "aws_opensearch_domain", "bastion_ip"}

	tfOutputs := terraform.OutputAll(t, terraformOptions)

	require.Len(t, tfOutputs, expectedOutputLength, "Output should contain %d items", expectedOutputLength)

	for _, val := range stringOutputs {
		_, ok := tfOutputs[val].(string)
		require.True(t, ok, fmt.Sprintf("Wrong data type for '%s', expected string, got %T", val, tfOutputs[val]))
		require.NotEmpty(t, tfOutputs[val], fmt.Sprintf("Output '%s' should not be empty", val))
	}

	ec2Instances, ok := tfOutputs["camunda_ips"].([]interface{})
	require.True(t, ok, fmt.Sprintf("Wrong data type for 'camunda_ips', expected []interface{}, got %T", tfOutputs["camunda_ips"]))
	require.Len(t, ec2Instances, expectedEc2Instances, "EC2 instances should contain %d items", expectedEc2Instances)

	// test connectivity to bastion host
	bastionIp := tfOutputs["bastion_ip"].(string)
	privateKey := tfOutputs["private_key"].(string)
	publicKey := tfOutputs["public_key"].(string)

	publicHost := ssh.Host{
		Hostname: bastionIp,
		SshKeyPair: &ssh.KeyPair{
			PrivateKey: privateKey,
			PublicKey:  publicKey,
		},
		SshUserName: "admin",
	}

	ssh.CheckSshConnectionWithRetry(t, publicHost, 5, 5)

	// test connectivity to private instances
	for _, ec2Instance := range ec2Instances {
		ec2Ip := ec2Instance.(string)

		privateHost := ssh.Host{
			Hostname: ec2Ip,
			SshKeyPair: &ssh.KeyPair{
				PrivateKey: privateKey,
				PublicKey:  publicKey,
			},
			SshUserName: "admin",
		}

		ssh.CheckPrivateSshConnection(t, publicHost, privateHost, "'exit'")
	}
}

func TestCreateAndConfigureSSH(t *testing.T) {
	t.Log("Configuring local ssh to work outside of Go")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformBinary: tfBinary,
		TerraformDir:    terraformDir,
		Vars:            tfVars,
		NoColor:         true,
		Logger:          logger.Discard, // disable logger due to sensitive data but will still log on error
	})

	tfOutputs := terraform.OutputAll(t, terraformOptions)

	// Write private key to file
	privateKey := tfOutputs["private_key"].(string)
	err := os.WriteFile(privKeyName, []byte(privateKey), 0600)
	if err != nil {
		log.Fatal(err)
	}

	// We are globally setting ssh settings to avoid ssh prompts
	// Additionally to keep the ssh commands in the scripts simple for end users
	// This is specific to the test environment and should not be used in production
	dir, err := os.Getwd()
	if err != nil {
		log.Fatal(err)
	}

	usr, err := user.Current()
	if err != nil {
		log.Fatal(err)
	}
	sshConfigPath := filepath.Join(usr.HomeDir, ".ssh", "config")

	configToAppend := `
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
		LogLevel ERROR
    IdentityFile ` + dir + `/` + privKeyName

	// Open the ssh config file in append mode, create if it doesn't exist
	file, err := os.OpenFile(sshConfigPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	_, err = file.WriteString(configToAppend)
	if err != nil {
		log.Fatal(err)
	}
}

func TestAllInOneScript(t *testing.T) {
	t.Log("Test all-in-one script")

	filePath := privKeyName
	attempts := 3

	for i := 0; i < attempts; i++ {
		if _, err := os.Stat(filePath); os.IsNotExist(err) {
			fmt.Printf("Private key does not exist: %s. Waiting for 60 seconds...\n", filePath)
			time.Sleep(60 * time.Second)
		} else {
			fmt.Println("Private key exists, continuing with the test...")
			break
		}
	}

	cmd := shell.Command{
		Command: "bash",
		Args:    []string{"-c", "../../scripts/all-in-one-install.sh"},
	}
	shell.RunCommand(t, cmd)
}

func TestCamundaSanityChecks(t *testing.T) {
	t.Log("Camunda sanity checks to confirm everything is working as expected")

	// TODO: deploy a diagram and check if it is running, trigger it, that kinda stuff
	// TODO: maybe some rest calls, Zeebe status etc. pp.
	// Make this into a helper function as this will likely be called multiple times

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformBinary: tfBinary,
		TerraformDir:    terraformDir,
		Vars:            tfVars,
		NoColor:         true,
		Logger:          logger.Discard, // disable logger due to sensitive data but will still log on error
	})

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

	var cluster Cluster
	err := json.Unmarshal([]byte(output), &cluster)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	require.Equal(t, 3, len(cluster.Brokers), "Expected 3 brokers, got %d", len(cluster.Brokers))
	require.Equal(t, 3, cluster.ClusterSize, "Expected static cluster size of 3, got %d", cluster.ClusterSize)

	for _, broker := range cluster.Brokers {
		require.Contains(t, broker.Host, "10.200.", "Broker host should be in the private subnet")
	}

	cmd = shell.Command{
		Command: "bash",
		Args:    []string{"-c", fmt.Sprintf("curl -f --cookie cookie.txt --form resources='@utils/single-task.bpmn' %s/v2/deployments -H 'Content-Type: multipart/form-data' -H 'Accept: application/json'", alb)},
	}
	output = shell.RunCommandAndGetStdOut(t, cmd)

	var deploymentInfo DeploymentInfo
	err = json.Unmarshal([]byte(output), &deploymentInfo)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	require.Equal(t, 1, len(deploymentInfo.Deployments), "Expected 1 deployment, got %d", len(deploymentInfo.Deployments))
	require.Equal(t, "single-task.bpmn", deploymentInfo.Deployments[0].ProcessDefinition.ResourceName, "Expected 'single-task.bpmn', got %s", deploymentInfo.Deployments[0].ProcessDefinition.ResourceName)
	require.Equal(t, "<default>", deploymentInfo.Deployments[0].ProcessDefinition.TenantId, "Expected '<default>', got %s", deploymentInfo.Deployments[0].ProcessDefinition.TenantId)

	cmd = shell.Command{
		Command: "bash",
		Args:    []string{"-c", fmt.Sprintf("curl -f --cookie cookie.txt -L -X POST %s/v2/process-instances -H 'Content-Type: application/json' -H 'Accept: application/json' --data-raw '{\"processDefinitionKey\":\"%d\"}'", alb, deploymentInfo.Deployments[0].ProcessDefinition.ProcessDefinitionKey)},
	}
	shell.RunCommand(t, cmd)

	// TODO: in the future when other REST APIs are available we could check that those have been deployed / run etc.
	// atm still limited to v1 API

	cmd = shell.Command{
		Command: "bash",
		Args:    []string{"-c", fmt.Sprintf("curl -f --cookie cookie.txt -L -X POST %s/v2/resources/%d/deletion", alb, deploymentInfo.Deployments[0].ProcessDefinition.ProcessDefinitionKey)},
	}
	shell.RunCommand(t, cmd)
}

func TestCloudWatchFeature(t *testing.T) {
	t.Log("Test CloudWatch feature")

	// TODO: run all-in-one-script.sh with cloudwatch enabled
}

func TestSecurityFeature(t *testing.T) {
	t.Log("Test security feature")

	// TODO: run all-in-one-script.sh with security enabled
}

func TestCamundaUpgrade(t *testing.T) {
	t.Log("Test Camunda upgrade")

	// TODO: Overwrite the Camunda version in `camunda-install.sh` and trigger all-in-one-script.sh
}

// func TestTeardown(t *testing.T) {
// 	t.Log("Test teardown")

// 	utils.OverwriteTerraformLifecycle(terraformDir + "/ec2.tf")

// 	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
// 		TerraformBinary: tfBinary,
// 		TerraformDir:    terraformDir,
// 		Vars:            tfVars,
// 		NoColor:         true,
// 	})

// 	terraform.Destroy(t, terraformOptions)
// }
