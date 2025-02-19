package test

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/eks"
	"github.com/aws/aws-sdk-go-v2/service/rds"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/camunda/camunda-tf-eks-module/utils"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/sethvargo/go-password/password"
	"github.com/stretchr/testify/suite"
	"go.uber.org/zap"
	"go.uber.org/zap/zaptest"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type CustomEKSRDSTestSuite struct {
	suite.Suite
	logger          *zap.Logger
	sugaredLogger   *zap.SugaredLogger
	clusterName     string
	expectedNodes   int
	kubeConfigPath  string
	region          string
	bucketRegion    string
	tfDataDir       string
	tfBinaryName    string
	varTf           map[string]interface{}
	tfStateS3Bucket string
}

func (suite *CustomEKSRDSTestSuite) SetupTest() {
	suite.logger = zaptest.NewLogger(suite.T())
	suite.sugaredLogger = suite.logger.Sugar()

	clusterSuffix := utils.GetEnv("TESTS_CLUSTER_ID", strings.ToLower(random.UniqueId()))
	suite.clusterName = fmt.Sprintf("cluster-rds-%s", clusterSuffix)
	suite.region = utils.GetEnv("TESTS_CLUSTER_REGION", "eu-central-1")
	suite.bucketRegion = utils.GetEnv("TF_STATE_BUCKET_REGION", suite.region)
	suite.tfBinaryName = utils.GetEnv("TESTS_TF_BINARY_NAME", "terraform")
	suite.sugaredLogger.Infow("Terraform binary for the suite", "binary", suite.tfBinaryName)

	suite.expectedNodes = 1
	var errAbsPath error
	suite.tfStateS3Bucket = utils.GetEnv("TF_STATE_BUCKET", fmt.Sprintf("tests-eks-tf-state-%s", suite.bucketRegion))
	suite.tfDataDir, errAbsPath = filepath.Abs(fmt.Sprintf("../../test/states/tf-data-%s", suite.clusterName))
	suite.Require().NoError(errAbsPath)
	suite.kubeConfigPath = fmt.Sprintf("%s/kubeconfig-rds-eks", suite.tfDataDir)
}

func (suite *CustomEKSRDSTestSuite) TearUpTest() {
	// create tf state
	absPath, err := filepath.Abs(suite.tfDataDir)
	suite.Require().NoError(err)
	err = os.MkdirAll(absPath, os.ModePerm)
	suite.Require().NoError(err)
}

func (suite *CustomEKSRDSTestSuite) TearDownTest() {
	suite.T().Log("Cleaning up resources...")

	err := os.Remove(suite.kubeConfigPath)
	if err != nil && !os.IsNotExist(err) {
		suite.T().Errorf("Failed to remove kubeConfigPath: %v", err)
	}
}

// TestCustomEKSAndRDS spawns a custom EKS cluster with custom parameters, and spawns a
// pg client pod that will test connection to AuroraDB
func (suite *CustomEKSRDSTestSuite) TestCustomEKSAndRDS() {
	suite.varTf = map[string]interface{}{
		"name":                  suite.clusterName,
		"region":                suite.region,
		"np_desired_node_count": suite.expectedNodes,
		// we test the definition of specific AZs, also RDS requires exactly 3AZs
		"availability_zones": []string{fmt.Sprintf("%sa", suite.region), fmt.Sprintf("%sb", suite.region), fmt.Sprintf("%sc", suite.region)},
	}

	suite.sugaredLogger.Infow("Creating EKS cluster...", "extraVars", suite.varTf)

	tfModuleEKS := "eks-cluster/"
	fullDirEKS := fmt.Sprintf("%s%s", suite.tfDataDir, tfModuleEKS)
	errTfDirEKS := os.MkdirAll(fullDirEKS, os.ModePerm)
	suite.Require().NoError(errTfDirEKS)
	tfDir := test_structure.CopyTerraformFolderToDest(suite.T(), "../../modules/", tfModuleEKS, fullDirEKS)

	errLinkBackend := os.Link("../../modules/fixtures/backend.tf", filepath.Join(tfDir, "backend.tf"))
	suite.Require().NoError(errLinkBackend)

	terraformOptions := &terraform.Options{
		TerraformBinary: suite.tfBinaryName,
		TerraformDir:    tfDir,
		Upgrade:         false,
		VarFiles:        []string{"../fixtures/fixtures.default.eks.tfvars"},
		Vars:            suite.varTf,
		BackendConfig: map[string]interface{}{
			"bucket": suite.tfStateS3Bucket,
			"key":    fmt.Sprintf("terraform/%s/TestCustomEKSRDSTestSuite/%sterraform.tfstate", suite.clusterName, tfModuleEKS),
			"region": suite.bucketRegion,
		},
	}

	// configure bucket backend
	sessBackend, err := utils.GetAwsClientF(utils.GetAwsProfile(), suite.bucketRegion)
	suite.Require().NoErrorf(err, "Failed to get aws client")
	err = utils.CreateS3BucketIfNotExists(sessBackend, suite.tfStateS3Bucket, utils.TF_BUCKET_DESCRIPTION, suite.bucketRegion)
	suite.Require().NoErrorf(err, "Failed to create s3 state bucket")

	cleanClusterAtTheEnd := utils.GetEnv("CLEAN_CLUSTER_AT_THE_END", "true")
	if cleanClusterAtTheEnd == "true" {
		defer utils.DeferCleanup(suite.T(), suite.bucketRegion, terraformOptions)
	}

	// due to output of the creation changing tags from null to {}, we can't pass the
	// idempotency test
	terraform.InitAndApply(suite.T(), terraformOptions)

	// basic tests after terraform apply
	expectedVpcAZs := fmt.Sprintf("[%sa %sb %sc]", suite.varTf["region"], suite.varTf["region"], suite.varTf["region"])
	suite.Assert().Equal(expectedVpcAZs, terraform.Output(suite.T(), terraformOptions, "vpc_azs"))

	sess, err := utils.GetAwsClient()
	suite.Require().NoErrorf(err, "Failed to get aws client")

	// list your services here
	eksSvc := eks.NewFromConfig(sess)
	rdsSvc := rds.NewFromConfig(sess)
	stsSvc := sts.NewFromConfig(sess)

	inputEKS := &eks.DescribeClusterInput{
		Name: aws.String(suite.clusterName),
	}

	result, err := eksSvc.DescribeCluster(context.Background(), inputEKS)
	suite.Assert().NoError(err)

	suite.sugaredLogger.Infow("Waiting for worker nodes to join the EKS cluster")
	errClusterReady := utils.WaitUntilKubeClusterIsReady(result.Cluster, 5*time.Minute, uint64(suite.expectedNodes))
	suite.Require().NoError(errClusterReady)

	// Spawn RDS within the EKS VPC/subnet
	publicBlocks := strings.Fields(strings.Trim(terraform.Output(suite.T(), terraformOptions, "public_vpc_cidr_blocks"), "[]"))
	privateBlocks := strings.Fields(strings.Trim(terraform.Output(suite.T(), terraformOptions, "private_vpc_cidr_blocks"), "[]"))

	// Extract OIDC issuer and create the IRSA role with RDS Aurora access
	oidcProviderID, errorOIDC := utils.ExtractOIDCProviderID(result)
	suite.Require().NoError(errorOIDC)

	stsIdentity, err := stsSvc.GetCallerIdentity(context.TODO(), &sts.GetCallerIdentityInput{})
	suite.Require().NoError(err, "Failed to get AWS account ID")

	accountId := *stsIdentity.Account
	auroraClusterName := fmt.Sprintf("postgres-%s", suite.clusterName)
	auroraUsername := "adminuser"
	auroraPassword, errPassword := password.Generate(18, 4, 0, false, false)
	suite.Require().NoError(errPassword)
	auroraDatabase := "camunda"

	// Define the ARN for RDS IAM DB Auth
	auroraIRSAUsername := "myirsauser"
	suite.sugaredLogger.Infow("Aurora RDS IAM infos", "accountId", accountId)

	utils.GenerateKubeConfigFromAWS(suite.T(), suite.region, suite.clusterName, utils.GetAwsProfile(), suite.kubeConfigPath)

	// Create namespace and associated service account in EKS
	auroraNamespace := "aurora"
	auroraServiceAccount := "aurora-access-sa"
	auroraRole := fmt.Sprintf("AuroraRole-%s", suite.clusterName)
	auroraKubectlOptions := k8s.NewKubectlOptions("", suite.kubeConfigPath, auroraNamespace)
	utils.CreateIfNotExistsNamespace(suite.T(), auroraKubectlOptions, auroraNamespace)
	utils.CreateIfNotExistsServiceAccount(suite.T(), auroraKubectlOptions, auroraServiceAccount, map[string]string{
		"eks.amazonaws.com/role-arn": fmt.Sprintf("arn:aws:iam::%s:role/%s", accountId, auroraRole),
	})

	// Define the Aurora access policy for IAM DB Auth
	auroraAccessPolicy := fmt.Sprintf(`{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds-db:connect"
      ],
      "Resource": "arn:aws:rds-db:%s:%s:dbuser:*/%s"
    }
  ]
}`, suite.region, accountId, auroraIRSAUsername)

	// Define the trust policy for Aurora IAM role
	iamRoleTrustPolicy := fmt.Sprintf(`{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::%s:oidc-provider/%s"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "%s:sub": "system:serviceaccount:%s:%s"
        }
      }
    }
  ]
}`, accountId, oidcProviderID, oidcProviderID, auroraNamespace, auroraServiceAccount)

	iamRolesWithPolicies := []interface{}{
		map[string]interface{}{
			"role_name": auroraRole,
			// escape and put everything on a single line
			"trust_policy":  strings.ReplaceAll(strings.ReplaceAll(iamRoleTrustPolicy, "\n", " "), `"`, `\"`),
			"access_policy": strings.ReplaceAll(strings.ReplaceAll(auroraAccessPolicy, "\n", " "), `"`, `\"`),
		},
	}

	varsConfigAurora := map[string]interface{}{
		"username":                auroraUsername,
		"password":                auroraPassword,
		"default_database_name":   auroraDatabase,
		"cluster_name":            auroraClusterName,
		"subnet_ids":              result.Cluster.ResourcesVpcConfig.SubnetIds,
		"vpc_id":                  *result.Cluster.ResourcesVpcConfig.VpcId,
		"availability_zones":      suite.varTf["availability_zones"], // we must match the zones of the EKS cluster
		"cidr_blocks":             append(publicBlocks, privateBlocks...),
		"iam_auth_enabled":        true,
		"iam_roles_with_policies": iamRolesWithPolicies,
	}

	tfModuleAurora := "aurora/"
	fullDirAurora := fmt.Sprintf("%s/%s", suite.tfDataDir, tfModuleAurora)
	errTfDirAurora := os.MkdirAll(fullDirAurora, os.ModePerm)
	suite.Require().NoError(errTfDirAurora)

	tfDirAurora := test_structure.CopyTerraformFolderToDest(suite.T(), "../../modules/", tfModuleAurora, fullDirAurora)

	errLinkBackend = os.Link("../../modules/fixtures/backend.tf", filepath.Join(tfDirAurora, "backend.tf"))
	suite.Require().NoError(errLinkBackend)

	terraformOptionsRDS := &terraform.Options{
		TerraformBinary: suite.tfBinaryName,
		TerraformDir:    tfDirAurora,
		Upgrade:         false,
		VarFiles:        []string{"../fixtures/fixtures.default.aurora.tfvars"},
		Vars:            varsConfigAurora,
		BackendConfig: map[string]interface{}{
			"bucket": suite.tfStateS3Bucket,
			"key":    fmt.Sprintf("terraform/%s/TestCustomEKSRDSTestSuite/%sterraform.tfstate", suite.clusterName, tfModuleAurora),
			"region": suite.bucketRegion,
		},
	}

	if cleanClusterAtTheEnd == "true" {
		defer utils.DeferCleanup(suite.T(), suite.bucketRegion, terraformOptionsRDS)
	}

	terraform.InitAndApplyAndIdempotent(suite.T(), terraformOptionsRDS)
	auroraEndpoint := terraform.Output(suite.T(), terraformOptionsRDS, "aurora_endpoint")
	suite.Assert().NotEmpty(auroraEndpoint)

	// Test of the RDS connection is performed by launching a pod on the cluster and test the pg connection
	pgKubeCtlOptions := k8s.NewKubectlOptions("", suite.kubeConfigPath, auroraNamespace)

	// deploy the postgres-client ConfigMap
	configMapPostgres := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "aurora-config",
			Namespace: auroraNamespace,
		},
		Data: map[string]string{
			"aurora_endpoint":      auroraEndpoint,
			"aurora_username":      auroraUsername,
			"aurora_password":      auroraPassword,
			"aurora_username_irsa": auroraIRSAUsername,
			"aurora_port":          "5432",
			"aws_region":           suite.region,
			"aurora_db_name":       auroraDatabase,
		},
	}

	// create a kubeclient
	kubeClient, err := utils.NewKubeClientSet(result.Cluster)
	suite.Require().NoError(err)

	err = kubeClient.CoreV1().ConfigMaps(auroraNamespace).Delete(context.Background(), configMapPostgres.Name, metav1.DeleteOptions{})
	if err != nil && !errors.IsNotFound(err) {
		suite.Require().NoError(err)
	}
	_, err = kubeClient.CoreV1().ConfigMaps(auroraNamespace).Create(context.Background(), configMapPostgres, metav1.CreateOptions{})
	k8s.WaitUntilConfigMapAvailable(suite.T(), pgKubeCtlOptions, configMapPostgres.Name, 6, 10*time.Second)

	// create the secret for aurora pg password
	secretPostgres := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "aurora-secret",
			Namespace: auroraNamespace,
		},
		StringData: map[string]string{
			"aurora_password": auroraPassword,
		},
	}
	err = kubeClient.CoreV1().Secrets(auroraNamespace).Delete(context.Background(), secretPostgres.Name, metav1.DeleteOptions{})
	if err != nil && !errors.IsNotFound(err) {
		suite.Require().NoError(err)
	}
	_, err = kubeClient.CoreV1().Secrets(auroraNamespace).Create(context.Background(), secretPostgres, metav1.CreateOptions{})
	k8s.WaitUntilSecretAvailable(suite.T(), pgKubeCtlOptions, secretPostgres.Name, 6, 10*time.Second)

	// cleanup existing jobs
	jobListOptions := metav1.ListOptions{LabelSelector: "app=postgres-client"}
	existingJobs := k8s.ListJobs(suite.T(), pgKubeCtlOptions, jobListOptions)
	backgroundDeletion := metav1.DeletePropagationBackground
	for _, job := range existingJobs {
		err := kubeClient.BatchV1().Jobs(auroraNamespace).Delete(context.Background(), job.Name, metav1.DeleteOptions{PropagationPolicy: &backgroundDeletion})
		suite.Assert().NoError(err)
	}

	// deploy the postgres-client Job to test the connection
	k8s.KubectlApply(suite.T(), pgKubeCtlOptions, "../../modules/fixtures/postgres-client.yml")
	errJob := utils.WaitForJobCompletion(kubeClient, auroraNamespace, "postgres-client", 5*time.Minute, jobListOptions)
	suite.Require().NoError(errJob)

	// Retrieve RDS information
	describeDBClusterInput := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: aws.String(varsConfigAurora["cluster_name"].(string)),
	}
	describeDBClusterOutput, err := rdsSvc.DescribeDBClusters(context.Background(), describeDBClusterInput)
	suite.Require().NoError(err)

	expectedRDSAZ := []string{fmt.Sprintf("%sa", suite.region), fmt.Sprintf("%sb", suite.region), fmt.Sprintf("%sc", suite.region)}
	suite.Assert().Equal(true, *describeDBClusterOutput.DBClusters[0].IAMDatabaseAuthenticationEnabled)
	suite.Assert().Equal(varsConfigAurora["username"].(string), *describeDBClusterOutput.DBClusters[0].MasterUsername)
	suite.Assert().Equal(auroraDatabase, *describeDBClusterOutput.DBClusters[0].DatabaseName)
	suite.Assert().Equal(int32(5432), *describeDBClusterOutput.DBClusters[0].Port)
	suite.Assert().ElementsMatch(expectedRDSAZ, describeDBClusterOutput.DBClusters[0].AvailabilityZones)
	suite.Assert().Equal(varsConfigAurora["cluster_name"].(string), *describeDBClusterOutput.DBClusters[0].DBClusterIdentifier)

	// Some of the tests are performed on the first instance of the cluster
	describeDBInstanceInput := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: describeDBClusterOutput.DBClusters[0].DBClusterMembers[0].DBInstanceIdentifier,
	}
	describeDBInstanceOutput, err := rdsSvc.DescribeDBInstances(context.Background(), describeDBInstanceInput)
	suite.Require().NoError(err)

	suite.Assert().Equal("db.t3.medium", *describeDBInstanceOutput.DBInstances[0].DBInstanceClass)
	suite.Assert().Equal(true, *describeDBInstanceOutput.DBInstances[0].AutoMinorVersionUpgrade)
	suite.Assert().Equal("aurora-postgresql", *describeDBInstanceOutput.DBInstances[0].Engine)
	suite.Assert().Equal("rds-ca-rsa2048-g1", *describeDBInstanceOutput.DBInstances[0].CertificateDetails.CAIdentifier)
	suite.Assert().Equal(varsConfigAurora["vpc_id"].(string), *describeDBInstanceOutput.DBInstances[0].DBSubnetGroup.VpcId)
	suite.Assert().Contains(*describeDBInstanceOutput.DBInstances[0].AvailabilityZone, suite.region)

	// construct the subnet ids
	actualSubnetIds := make([]string, len(describeDBInstanceOutput.DBInstances[0].DBSubnetGroup.Subnets))
	for id, subnet := range describeDBInstanceOutput.DBInstances[0].DBSubnetGroup.Subnets {
		actualSubnetIds[id] = *subnet.SubnetIdentifier
	}
	suite.Assert().ElementsMatch(varsConfigAurora["subnet_ids"].([]string), actualSubnetIds)

	// EKS test that custom cluster parameters are applied as expected

	// count nb of nodes
	nodes, err := kubeClient.CoreV1().Nodes().List(context.Background(), metav1.ListOptions{})
	suite.Require().NoError(err)
	suite.Assert().Equal(suite.expectedNodes, len(nodes.Items))

	// verifies for each node, the flavor and the region
	expectedInstanceType := "t2.medium"
	for _, node := range nodes.Items {
		regionNode, _ := node.Labels["failure-domain.beta.kubernetes.io/region"]
		instanceType, _ := node.Labels["node.kubernetes.io/instance-type"]
		for _, addr := range node.Status.Addresses {
			if addr.Type == "InternalIP" {
				suite.Assert().Equal(suite.region, regionNode)
				suite.Assert().Equal(expectedInstanceType, instanceType)
			}
		}
	}
}

func TestCustomEKSRDSTestSuite(t *testing.T) {
	t.Parallel()
	suite.Run(t, new(CustomEKSRDSTestSuite))
}
