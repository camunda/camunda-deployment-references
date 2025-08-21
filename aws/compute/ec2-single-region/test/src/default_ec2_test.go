package test

import (
	"context"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/camunda/camunda-deployment-references/aws/ec2/utils"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

const (
	privKeyName  = "ec2-jar-priv"
	logGroupName = "camunda"
)

var (
	terraformDir  = utils.GetEnv("TERRAFORM_DIR", "../../terraform/cluster")
	tfBinary      = utils.GetEnv("TERRAFORM_BINARY", "terraform")
	adminUsername = utils.GetEnv("ADMIN_USERNAME", "ubuntu")
	tfVars        = map[string]interface{}{
		"prefix":                    utils.GetEnv("TF_PREFIX", "ec2-jar-test"),
		"opensearch_architecture":   utils.GetEnv("ARCHITECTURE", "x86_64"),
		"aws_instance_architecture": utils.GetEnv("ARCHITECTURE", "x86_64"),
		"generate_ssh_key_pair":     true,
	}
)

func terraformOptions(t *testing.T, logType *logger.Logger) *terraform.Options {
	tmpLogType := logType
	if logType == nil {
		tmpLogType = logger.Default
	}

	return terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformBinary: tfBinary,
		TerraformDir:    terraformDir,
		Vars:            tfVars,
		NoColor:         true,
		Logger:          tmpLogType,
	})
}

func TestSetup(t *testing.T) {
	t.Log("Test setup")

	terraform.InitAndApply(t, terraformOptions(t, nil))
}

func TestConnectivity(t *testing.T) {
	t.Log("Test connectivity to EC2 instances")

	// expected values
	expectedOutputLength := 9
	expectedEc2Instances := 3

	stringOutputs := [...]string{"aws_ami", "alb_endpoint", "nlb_endpoint", "private_key", "public_key", "aws_opensearch_domain", "aws_opensearch_domain_name", "bastion_ip"}

	tfOutputs := terraform.OutputAll(t, terraformOptions(t, logger.Discard))

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
		SshUserName: adminUsername,
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
			SshUserName: adminUsername,
		}

		ssh.CheckPrivateSshConnection(t, publicHost, privateHost, "'exit'")
	}
}

func TestCreateAndConfigureSSH(t *testing.T) {
	t.Log("Configuring local ssh to work outside of Go")

	tfOutputs := terraform.OutputAll(t, terraformOptions(t, logger.Discard))

	// Write private key to file
	privateKey := tfOutputs["private_key"].(string)
	err := os.WriteFile(privKeyName, []byte(privateKey), 0600)
	if err != nil {
		t.Fatal(err)
	}

	// We are globally setting ssh settings to avoid ssh prompts
	// Additionally to keep the ssh commands in the scripts simple for end users
	// This is specific to the test environment and should not be used in production
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}

	usr, err := user.Current()
	if err != nil {
		t.Fatal(err)
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
		t.Fatal(err)
	}
	defer file.Close()

	_, err = file.WriteString(configToAppend)
	if err != nil {
		t.Fatal(err)
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
		Args:    []string{"-c", "../../procedure/all-in-one-install.sh"},
	}
	shell.RunCommand(t, cmd)
}

func TestCamundaSanityChecks(t *testing.T) {
	t.Log("Camunda sanity checks to confirm everything is working as expected")

	utils.APICheckCorrectCamundaVersion(t, terraformOptions(t, logger.Discard), "")
	utils.APIDeployAndStartWorkflow(t, terraformOptions(t, logger.Discard))
}

func TestCloudWatchFeature(t *testing.T) {
	t.Log("Test CloudWatch feature")

	tfOutputs := terraform.OutputAll(t, terraformOptions(t, logger.Discard))
	bastionIp := tfOutputs["bastion_ip"].(string)
	camundaIps := tfOutputs["camunda_ips"].([]interface{})

	filePath := privKeyName
	attempts := 3

	for i := 0; i < attempts; i++ {
		if _, err := os.Stat(filePath); os.IsNotExist(err) {
			t.Logf("Private key does not exist: %s. Waiting for 60 seconds...\n", filePath)
			time.Sleep(60 * time.Second)
		} else {
			t.Log("Private key exists, continuing with the test...")
			break
		}
	}

	cmd := shell.Command{
		Command: "bash",
		Args:    []string{"-c", "export CLOUDWATCH_ENABLED=true && ../../procedure/all-in-one-install.sh"},
	}
	output := shell.RunCommandAndGetStdOut(t, cmd)

	require.Contains(t, output, "CloudWatch monitoring is set to: true.", "Expected CloudWatch to be enabled")

	cmd = shell.Command{
		Command: "ssh",
		Args:    []string{"-J", fmt.Sprintf("%s@%s", adminUsername, bastionIp), fmt.Sprintf("%s@%s", adminUsername, camundaIps[0]), "sudo systemctl is-active amazon-cloudwatch-agent"},
	}
	output = shell.RunCommandAndGetStdOut(t, cmd)

	require.Contains(t, output, "active", "Expected CloudWatch agent to be active")

	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		t.Fatalf("unable to load AWS SDK config, %v", err)
	}

	svc := cloudwatchlogs.NewFromConfig(cfg)

	input := &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: aws.String(logGroupName),
	}

	resp, err := svc.DescribeLogGroups(context.TODO(), input)
	if err != nil {
		t.Fatalf("failed to describe log groups, %v", err)
	}

	exists := false
	for _, group := range resp.LogGroups {
		if *group.LogGroupName == logGroupName {
			exists = true
			break
		}
	}

	if exists {
		t.Logf("Log group '%s' exists.\n", logGroupName)
	} else {
		t.Fatalf("Log group '%s' does not exist.\n", logGroupName)
	}
}

func TestCamundaUpgrade(t *testing.T) {
	t.Log("Test Camunda upgrade")

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

	utils.ResetCamunda(t, terraformOptions(t, logger.Discard), adminUsername)

	filePath = "../../procedure/camunda-install.sh"

	content, err := os.ReadFile(filePath)
	if err != nil {
		t.Fatalf("Error reading file: %v", err)
	}

	fileContent := string(content)

	re := regexp.MustCompile(`:-"(([0-9]+\.[0-9]+\.[0-9]+)(-SNAPSHOT|-alpha[0-9]+)?)"`)
	match := re.FindAllStringSubmatch(fileContent, -1)

	fmt.Println("Match:", match)

	if len(match) < 2 {
		t.Fatalf("Expected at least 2 matches found in file: %s, got: %d", filePath, len(match))
	}

	camundaCurrentVersion := match[0][2]     // Base version without suffix
	camundaCurrentVersionFull := match[0][1] // Full version with suffix
	camundaPreviousVersion, err := utils.LowerVersion(camundaCurrentVersion)
	if err != nil {
		t.Fatalf("Error lowering version: %v", err)
	}

	connectorsCurrentVersion := match[1][2]     // Base version without suffix
	connectorsCurrentVersionFull := match[1][1] // Full version with suffix
	connectorsPreviousVersion, err := utils.LowerVersion(connectorsCurrentVersion)
	if err != nil {
		t.Fatalf("Error lowering version: %v", err)
	}

	// Allows overwriting the versions from outside
	camundaCurrentVersionFull = utils.GetEnv("CAMUNDA_VERSION", camundaCurrentVersionFull)
	camundaPreviousVersion = utils.GetEnv("CAMUNDA_PREVIOUS_VERSION", camundaPreviousVersion)
	connectorsCurrentVersionFull = utils.GetEnv("CAMUNDA_CONNECTORS_VERSION", connectorsCurrentVersionFull)
	connectorsPreviousVersion = utils.GetEnv("CAMUNDA_CONNECTORS_PREVIOUS_VERSION", connectorsPreviousVersion)

	t.Logf("Camunda current version: %s, previous version: %s", camundaCurrentVersionFull, camundaPreviousVersion)
	t.Logf("Connectors current version: %s, previous version: %s", connectorsCurrentVersionFull, connectorsPreviousVersion)

	camundaVersionRegex := regexp.MustCompile(`CAMUNDA_VERSION=\$\{CAMUNDA_VERSION:-"[^"]*"\}`)
	updatedContent := camundaVersionRegex.ReplaceAllString(fileContent, fmt.Sprintf("CAMUNDA_VERSION=%s", camundaPreviousVersion))

	connectorsVersionRegex := regexp.MustCompile(`CAMUNDA_CONNECTORS_VERSION=\$\{CAMUNDA_CONNECTORS_VERSION:-"[^"]*"\}`)
	updatedContent = connectorsVersionRegex.ReplaceAllString(updatedContent, fmt.Sprintf("CAMUNDA_CONNECTORS_VERSION=%s", connectorsPreviousVersion))

	err = os.WriteFile(filePath, []byte(updatedContent), 0644)
	if err != nil {
		t.Fatalf("Error writing file: %v", err)
	}

	t.Logf("Running all-in-one script with Camunda version: %s, Connectors version: %s", camundaPreviousVersion, connectorsPreviousVersion)
	cmd := shell.Command{
		Command: "bash",
		Args:    []string{"-c", "../../procedure/all-in-one-install.sh"},
	}
	shell.RunCommand(t, cmd)

	utils.APICheckCorrectCamundaVersion(t, terraformOptions(t, logger.Discard), camundaPreviousVersion)

	t.Logf("Restoring file: %s", filePath)
	err = os.WriteFile(filePath, []byte(fileContent), 0644)
	if err != nil {
		t.Fatalf("Error writing file: %v", err)
	}

	// Zeebe has a prerelease protection that results in unhealthy clusters if not disabled
	if strings.Contains(camundaCurrentVersionFull, "SNAPSHOT") || strings.Contains(camundaCurrentVersionFull, "alpha") {
		cmd = shell.Command{
			Command: "bash",
			Args:    []string{"-c", "echo ZEEBE_BROKER_EXPERIMENTAL_VERSIONCHECKRESTRICTIONENABLED=false >> ../../configs/camunda-environment"},
		}
		shell.RunCommand(t, cmd)
	}

	t.Logf("Running all-in-one script with Camunda version: %s, Connectors version: %s", camundaCurrentVersionFull, connectorsCurrentVersionFull)
	cmd = shell.Command{
		Command: "bash",
		Args:    []string{"-c", "../../procedure/all-in-one-install.sh"},
	}
	output := shell.RunCommandAndGetOutput(t, cmd)

	require.Contains(t, output, "Detected existing Camunda installation.", "Expected existing Camunda installation message")

	utils.APICheckCorrectCamundaVersion(t, terraformOptions(t, logger.Discard), camundaCurrentVersionFull)
}

func TestTeardown(t *testing.T) {
	t.Log("Test teardown")

	terraform.Destroy(t, terraformOptions(t, nil))

	t.Log("Removing CloudWatch log group")
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		t.Fatalf("unable to load SDK config, %v", err)
	}

	svc := cloudwatchlogs.NewFromConfig(cfg)

	input := &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: aws.String(logGroupName),
	}

	resp, err := svc.DescribeLogGroups(context.TODO(), input)
	if err != nil {
		t.Fatalf("failed to describe log groups, %v", err)
	}

	exists := false
	for _, group := range resp.LogGroups {
		if *group.LogGroupName == logGroupName {
			exists = true
			break
		}
	}

	if !exists {
		t.Logf("Log group '%s' does not exist.\n", logGroupName)
		return
	} else {
		t.Log("Deleting log group...")
		_, err = svc.DeleteLogGroup(context.TODO(), &cloudwatchlogs.DeleteLogGroupInput{
			LogGroupName: aws.String(logGroupName),
		})

		if err != nil {
			t.Fatalf("failed to delete log group '%s', %v", logGroupName, err)
		}

		t.Logf("Log group '%s' deleted successfully.\n", logGroupName)
	}
}
