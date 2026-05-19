package test

import (
	"testing"

	"multiregiontests/internal/helpers"
	awsHelpers "multiregiontests/internal/helpers/aws"

	"github.com/gruntwork-io/terratest/modules/k8s"
)

var tfBinary = helpers.GetEnv("TESTS_TF_BINARY_NAME", "terraform")

// Terraform Cluster Setup and TearDown

func TestSetupTerraform(t *testing.T) {
	t.Log("[TF SETUP] Applying Terraform config 👋")
	awsHelpers.TestSetupTerraform(t, terraformDir, clusterName, awsProfile, tfBinary)
}

func TestAWSKubeConfigCreation(t *testing.T) {
	t.Log("[KUBECONFIG] Creating kubeconfig files 🚀")
	awsHelpers.GenerateAWSKubeConfig(t, clusterName, awsProfile, "us-east-1", "us-east-1")
	awsHelpers.GenerateAWSKubeConfig(t, clusterName, awsProfile, "us-east-2", "us-east-2")
}

func TestTeardownTerraform(t *testing.T) {
	t.Log("[TF TEARDOWN] Destroying workspace 🖖")
	awsHelpers.TestTeardownTerraform(t, terraformDir, clusterName, awsProfile, tfBinary)
}

func TestAWSKubeConfigRemoval(t *testing.T) {
	t.Log("[KUBECONFIG] Removing kubeconfig files 🗑️")
	awsHelpers.TestRemoveKubeConfig(t, "us-east-1")
	awsHelpers.TestRemoveKubeConfig(t, "us-east-2")
}

func TestClusterCleanup(t *testing.T) {
	t.Log("[CLEANUP] Cleaning up resources 🧹")

	for _, testFuncs := range []struct {
		name  string
		tfunc func(*testing.T)
	}{
		{"TestInitKubernetesHelpers", initKubernetesHelpers},
		{"TestCleanupKubernetes", cleanupKubernetes},
	} {
		t.Run(testFuncs.name, testFuncs.tfunc)
	}
}

func cleanupKubernetes(t *testing.T) {
	t.Log("[K8S CLEANUP] Cleaning up Kubernetes resources 🧹")

	k8s.RunKubectl(t, &primary.KubectlSystem, "delete", "--ignore-not-found=true", "service", "internal-dns-lb")
	k8s.RunKubectl(t, &secondary.KubectlSystem, "delete", "--ignore-not-found=true", "service", "internal-dns-lb")
}
