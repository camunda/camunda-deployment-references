package test

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/eks"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/opensearch"
	"github.com/aws/aws-sdk-go-v2/service/opensearch/types"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/camunda/camunda-tf-eks-module/utils"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
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

type CustomEKSOpenSearchTestSuite struct {
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

func (suite *CustomEKSOpenSearchTestSuite) SetupTest() {
	suite.logger = zaptest.NewLogger(suite.T())
	suite.sugaredLogger = suite.logger.Sugar()

	clusterSuffix := utils.GetEnv("TESTS_CLUSTER_ID", strings.ToLower(random.UniqueId()))
	suite.clusterName = fmt.Sprintf("cl-os-%s", clusterSuffix)
	suite.region = utils.GetEnv("TESTS_CLUSTER_REGION", "eu-central-1")
	suite.bucketRegion = utils.GetEnv("TF_STATE_BUCKET_REGION", suite.region)
	suite.tfBinaryName = utils.GetEnv("TESTS_TF_BINARY_NAME", "terraform")
	suite.sugaredLogger.Infow("Terraform binary for the suite", "binary", suite.tfBinaryName)

	suite.expectedNodes = 1
	var errAbsPath error
	suite.tfStateS3Bucket = utils.GetEnv("TF_STATE_BUCKET", fmt.Sprintf("tests-eks-tf-state-%s", suite.bucketRegion))
	suite.tfDataDir, errAbsPath = filepath.Abs(fmt.Sprintf("../../test/states/tf-data-%s", suite.clusterName))
	suite.Require().NoError(errAbsPath)
	suite.kubeConfigPath = fmt.Sprintf("%s/kubeconfig-opensearch-eks", suite.tfDataDir)
}

func (suite *CustomEKSOpenSearchTestSuite) TearUpTest() {
	// create tf state
	absPath, err := filepath.Abs(suite.tfDataDir)
	suite.Require().NoError(err)
	err = os.MkdirAll(absPath, os.ModePerm)
	suite.Require().NoError(err)
}

func (suite *CustomEKSOpenSearchTestSuite) TearDownTest() {
	suite.T().Log("Cleaning up resources...")

	err := os.Remove(suite.kubeConfigPath)
	if err != nil && !os.IsNotExist(err) {
		suite.T().Errorf("Failed to remove kubeConfigPath: %v", err)
	}
}

// TestCustomEKSAndOpenSearch spawns a custom EKS cluster with custom parameters, and spawns a
// a curl pod that will try to reach the OpenSearch cluster
func (suite *CustomEKSOpenSearchTestSuite) TestCustomEKSAndOpenSearch() {
	suite.varTf = map[string]interface{}{
		"name":                  suite.clusterName,
		"region":                suite.region,
		"np_desired_node_count": suite.expectedNodes,
		// we test the usage of a two zones (minimum)
		"availability_zones_count": 2,
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
			"key":    fmt.Sprintf("terraform/%s/TestCustomEKSOpenSearchTestSuite/%sterraform.tfstate", suite.clusterName, tfModuleEKS),
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

	expectedVpcAZs := fmt.Sprintf("[%sa %sb]", suite.varTf["region"], suite.varTf["region"]) // must match availability_zones_count
	suite.Assert().Equal(expectedVpcAZs, terraform.Output(suite.T(), terraformOptions, "vpc_azs"))

	// this is a split(4)[0..1] of the base cluster_node_ipv4_cidr    = "10.192.0.0/16"
	expectedPrivateVpcCidrBlocks := "[10.192.0.0/18 10.192.64.0/18]"
	suite.Assert().Equal(expectedPrivateVpcCidrBlocks, terraform.Output(suite.T(), terraformOptions, "private_vpc_cidr_blocks"))

	// this is a split(4)[2..1] of the base cluster_node_ipv4_cidr    = "10.192.0.0/16"
	expectedPublicVpcCidrBlocks := "[10.192.128.0/18 10.192.192.0/18]"
	suite.Assert().Equal(expectedPublicVpcCidrBlocks, terraform.Output(suite.T(), terraformOptions, "public_vpc_cidr_blocks"))

	sess, err := utils.GetAwsClient()
	suite.Require().NoErrorf(err, "Failed to get aws client")

	eksSvc := eks.NewFromConfig(sess)
	openSearchSvc := opensearch.NewFromConfig(sess)
	stsSvc := sts.NewFromConfig(sess)
	iamSvc := iam.NewFromConfig(sess)

	inputEKS := &eks.DescribeClusterInput{
		Name: aws.String(suite.clusterName),
	}

	result, err := eksSvc.DescribeCluster(context.Background(), inputEKS)
	suite.sugaredLogger.Infow("eks describe cluster result", "result", result, "err", err)
	suite.Assert().NoError(err)

	utils.GenerateKubeConfigFromAWS(suite.T(), suite.region, suite.clusterName, utils.GetAwsProfile(), suite.kubeConfigPath)

	// Spawn OpenSearch within the EKS VPC/subnet
	publicBlocks := strings.Fields(strings.Trim(terraform.Output(suite.T(), terraformOptions, "public_vpc_cidr_blocks"), "[]"))
	privateBlocks := strings.Fields(strings.Trim(terraform.Output(suite.T(), terraformOptions, "private_vpc_cidr_blocks"), "[]"))

	opensearchDomainName := fmt.Sprintf("os-%s", suite.clusterName)

	// Extract OIDC issuer and create the IRSA role with RDS OpenSearch access
	oidcProviderID, errorOIDC := utils.ExtractOIDCProviderID(result)
	suite.Require().NoError(errorOIDC)
	suite.Assert().NotEmpty(terraform.Output(suite.T(), terraformOptions, "oidc_provider_id"))
	suite.Require().Equal(oidcProviderID, terraform.Output(suite.T(), terraformOptions, "oidc_provider_id"))

	stsIdentity, err := stsSvc.GetCallerIdentity(context.TODO(), &sts.GetCallerIdentityInput{})
	suite.Require().NoError(err, "Failed to get AWS account ID")
	accountId := *stsIdentity.Account
	suite.Assert().NotEmpty(terraform.Output(suite.T(), terraformOptions, "aws_caller_identity_account_id"))
	suite.Require().Equal(accountId, terraform.Output(suite.T(), terraformOptions, "aws_caller_identity_account_id"))

	openSearchArn := fmt.Sprintf("arn:aws:es:%s:%s:domain/%s/*", suite.region, accountId, opensearchDomainName)
	suite.sugaredLogger.Infow("OpenSearch infos", "accountId", accountId, "openSearchArn", openSearchArn)

	// Create namespace and associated service account in EKS
	openSearchNamespace := "opensearch"
	openSearchServiceAccount := "opensearch-access-sa"
	openSearchRole := fmt.Sprintf("OpenSearchRole-%s", suite.clusterName)
	openSearchKubectlOptions := k8s.NewKubectlOptions("", suite.kubeConfigPath, openSearchNamespace)
	utils.CreateIfNotExistsNamespace(suite.T(), openSearchKubectlOptions, openSearchNamespace)
	utils.CreateIfNotExistsServiceAccount(suite.T(), openSearchKubectlOptions, openSearchServiceAccount, map[string]string{
		"eks.amazonaws.com/role-arn": fmt.Sprintf("arn:aws:iam::%s:role/%s", accountId, openSearchRole),
	})

	openSearchAccessPolicy := fmt.Sprintf(`{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "es:ESHttpGet",
        "es:ESHttpPut",
        "es:ESHttpPost"
      ],
      "Resource": "arn:aws:es:%s:%s:domain/%s/*"
    }
  ]
}`, suite.region, accountId, opensearchDomainName)

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
}`, accountId, oidcProviderID, oidcProviderID, openSearchNamespace, openSearchServiceAccount)

	iamRolesWithPolicies := []interface{}{
		map[string]interface{}{
			"role_name": openSearchRole,
			// escape and put everything on a single line
			"trust_policy":  strings.ReplaceAll(strings.ReplaceAll(iamRoleTrustPolicy, "\n", " "), `"`, `\"`),
			"access_policy": strings.ReplaceAll(strings.ReplaceAll(openSearchAccessPolicy, "\n", " "), `"`, `\"`),
		},
	}

	varsConfigOpenSearch := map[string]interface{}{
		"domain_name":                            opensearchDomainName,
		"subnet_ids":                             result.Cluster.ResourcesVpcConfig.SubnetIds,
		"cidr_blocks":                            append(publicBlocks, privateBlocks...),
		"vpc_id":                                 *result.Cluster.ResourcesVpcConfig.VpcId,
		"iam_roles_with_policies":                iamRolesWithPolicies,
		"zone_awareness_availability_zone_count": suite.varTf["availability_zones_count"], // must match VPC AZs of EKS
		"instance_count":                         2,                                       // we must choose an even number of data nodes for a two Availability Zone deployment
	}

	tfModuleOpenSearch := "opensearch/"
	fullDirOpenSearch := fmt.Sprintf("%s/%s", suite.tfDataDir, tfModuleOpenSearch)
	errTfDirOpenSearch := os.MkdirAll(fullDirOpenSearch, os.ModePerm)
	suite.Require().NoError(errTfDirOpenSearch)

	tfDirOpenSearch := test_structure.CopyTerraformFolderToDest(suite.T(), "../../modules/", tfModuleOpenSearch, fullDirOpenSearch)

	errLinkBackend = os.Link("../../modules/fixtures/backend.tf", filepath.Join(tfDirOpenSearch, "backend.tf"))
	suite.Require().NoError(errLinkBackend)

	terraformOptionsOpenSearch := &terraform.Options{
		TerraformBinary: suite.tfBinaryName,
		TerraformDir:    tfDirOpenSearch,
		Upgrade:         false,
		VarFiles:        []string{"../fixtures/fixtures.default.opensearch.tfvars"},
		Vars:            varsConfigOpenSearch,
		BackendConfig: map[string]interface{}{
			"bucket": suite.tfStateS3Bucket,
			"key":    fmt.Sprintf("terraform/%s/TestCustomEKSOpenSearchTestSuite/%sterraform.tfstate", suite.clusterName, tfModuleOpenSearch),
			"region": suite.bucketRegion,
		},
	}

	if cleanClusterAtTheEnd == "true" {
		defer utils.DeferCleanup(suite.T(), suite.bucketRegion, terraformOptionsOpenSearch)
	}

	terraform.InitAndApplyAndIdempotent(suite.T(), terraformOptionsOpenSearch)
	opensearchEndpoint := terraform.Output(suite.T(), terraformOptionsOpenSearch, "opensearch_domain_endpoint")
	suite.Assert().NotEmpty(opensearchEndpoint)

	// Test the OpenSearch connection and perform additional tests as needed

	// Retrieve OpenSearch information
	describeDomainInput := &opensearch.DescribeDomainInput{
		DomainName: aws.String(varsConfigOpenSearch["domain_name"].(string)),
	}
	describeOpenSearchDomainOutput, err := openSearchSvc.DescribeDomain(context.Background(), describeDomainInput)
	suite.Require().NoError(err)
	suite.sugaredLogger.Infow("Domain info", "domain", describeOpenSearchDomainOutput)

	suite.sugaredLogger.Infow("DescribeDomain info", "domain", describeOpenSearchDomainOutput.DomainStatus.EngineVersion)

	// Perform assertions on the OpenSearch domain configuration
	suite.Assert().Equal(varsConfigOpenSearch["domain_name"].(string), *describeOpenSearchDomainOutput.DomainStatus.DomainName)
	suite.Assert().Equal(int32(2), *describeOpenSearchDomainOutput.DomainStatus.ClusterConfig.InstanceCount)
	suite.Assert().Equal(types.OpenSearchPartitionInstanceType("t3.small.search"), describeOpenSearchDomainOutput.DomainStatus.ClusterConfig.InstanceType)
	suite.Assert().Equal(varsConfigOpenSearch["vpc_id"].(string), *describeOpenSearchDomainOutput.DomainStatus.VPCOptions.VPCId)

	// Verify security group information
	suite.Assert().NotEmpty(describeOpenSearchDomainOutput.DomainStatus.VPCOptions.SecurityGroupIds)

	// Retrieve the IAM Role associated with OpenSearch
	describeOpenSearchRoleInput := &iam.GetRoleInput{
		RoleName: aws.String(openSearchRole),
	}
	_, err = iamSvc.GetRole(context.Background(), describeOpenSearchRoleInput)
	suite.Require().NoError(err)

	// Verify IAM Policy Attachment
	listAttachedPoliciesInput := &iam.ListAttachedRolePoliciesInput{
		RoleName: aws.String(openSearchRole),
	}
	_, err = iamSvc.ListAttachedRolePolicies(context.Background(), listAttachedPoliciesInput)
	suite.Require().NoError(err)

	// Test the OpenSearch connection and perform additional tests as needed
	suite.Assert().NotEmpty(opensearchEndpoint)
	configMapScript := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "opensearch-config",
			Namespace: openSearchNamespace,
		},
		Data: map[string]string{
			"opensearch_endpoint": opensearchEndpoint,
			"aws_region":          suite.region,
		},
	}

	// spawn a kubeclient
	kubeClient, errKubeClient := utils.NewKubeClientSet(result.Cluster)
	suite.Require().NoError(errKubeClient)

	err = kubeClient.CoreV1().ConfigMaps(openSearchNamespace).Delete(context.Background(), configMapScript.Name, metav1.DeleteOptions{})
	if err != nil && !errors.IsNotFound(err) {
		suite.Require().NoError(err)
	}
	_, err = kubeClient.CoreV1().ConfigMaps(openSearchNamespace).Create(context.Background(), configMapScript, metav1.CreateOptions{})
	k8s.WaitUntilConfigMapAvailable(suite.T(), openSearchKubectlOptions, configMapScript.Name, 6, 10*time.Second)

	// cleanup existing jobs
	jobListOptions := metav1.ListOptions{LabelSelector: "app=opensearch-client"}
	existingJobs := k8s.ListJobs(suite.T(), openSearchKubectlOptions, jobListOptions)
	backgroundDeletion := metav1.DeletePropagationBackground
	for _, job := range existingJobs {
		err := kubeClient.BatchV1().Jobs(openSearchNamespace).Delete(context.Background(), job.Name, metav1.DeleteOptions{PropagationPolicy: &backgroundDeletion})
		suite.Assert().NoError(err)
	}

	// deploy the opensearch-client Job to test the connection
	k8s.KubectlApply(suite.T(), openSearchKubectlOptions, "../../modules/fixtures/opensearch-client.yml")
	errJob := utils.WaitForJobCompletion(kubeClient, openSearchNamespace, "opensearch-client", 5*time.Minute, jobListOptions)
	suite.Require().NoError(errJob)
}

func TestCustomEKSOpenSearchTestSuite(t *testing.T) {
	t.Parallel()
	suite.Run(t, new(CustomEKSOpenSearchTestSuite))
}
