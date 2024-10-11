package test

import (
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
