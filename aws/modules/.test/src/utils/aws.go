package utils

import (
	"context"
	"errors"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/eks"
	"github.com/aws/aws-sdk-go-v2/service/eks/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	types2 "github.com/aws/aws-sdk-go-v2/service/s3/types"
	"net/http"
	"strings"
	"time"
)

func GetAwsProfile() string {
	return GetEnv("AWS_PROFILE", GetEnv("AWS_DEFAULT_PROFILE", "infex"))
}

func GetAwsRegion() string {
	return GetEnv("AWS_REGION", "eu-central-1")
}

// GetAwsClient returns an aws.Config client from the env variables `AWS_PROFILE` and `AWS_REGION`
func GetAwsClient() (aws.Config, error) {
	return GetAwsClientF(GetAwsProfile(), GetAwsRegion())
}

// GetAwsClientF returns an aws.Config client
func GetAwsClientF(profile, region string) (aws.Config, error) {
	return config.LoadDefaultConfig(context.TODO(),
		config.WithRegion(region),
		config.WithSharedConfigProfile(profile),
	)
}

func WaitForUpdateEKS(ctx context.Context, client *eks.Client, clusterName, updateID string) error {
	describeUpdateInput := &eks.DescribeUpdateInput{
		Name:     &clusterName,
		UpdateId: &updateID,
	}

L:
	for {
		updateOutput, err := client.DescribeUpdate(ctx, describeUpdateInput)
		if err != nil {
			return err
		}

		status := updateOutput.Update.Status
		fmt.Printf("Update status: %s\n", status)

		switch status {
		case types.UpdateStatusFailed:
			return fmt.Errorf("update failed")
		case types.UpdateStatusCancelled:
			return fmt.Errorf("update cancelled")
		case types.UpdateStatusSuccessful:
			break L
		case types.UpdateStatusInProgress:
			time.Sleep(5 * time.Second)
		default:
			return fmt.Errorf("update status unknown: %s", status)
		}
	}

	return nil
}

func UpgradeEKS(ctx context.Context, client *eks.Client, clusterName, version string) error {
	input := &eks.UpdateClusterVersionInput{
		Name:    &clusterName,
		Version: &version,
	}

	output, err := client.UpdateClusterVersion(ctx, input)
	if err != nil {
		return err
	}

	fmt.Printf("Update initiated, update ID: %s\n", *output.Update.Id)

	err = WaitForUpdateEKS(ctx, client, clusterName, *output.Update.Id)
	if err != nil {
		return err
	}

	fmt.Println("Update completed successfully")
	return nil
}

func CreateS3BucketIfNotExists(sess aws.Config, s3Bucket string, description string, region string) error {
	s3Client := s3.NewFromConfig(sess)

	// Check if the bucket already exists
	_, err := s3Client.HeadBucket(context.TODO(), &s3.HeadBucketInput{
		Bucket: aws.String(s3Bucket),
	})

	if err == nil {
		// Bucket already exists
		fmt.Printf("Bucket %s already exists\n", s3Bucket)
		return nil
	} else {
		var responseError *awshttp.ResponseError
		if errors.As(err, &responseError) && responseError.ResponseError.HTTPStatusCode() == http.StatusNotFound {
			fmt.Printf("Bucket %s does not exist\n", s3Bucket)
		} else {
			return fmt.Errorf("failed to check if bucket exists: %v", err)
		}
	}

	// Create the S3 bucket
	_, err = s3Client.CreateBucket(context.TODO(), &s3.CreateBucketInput{
		Bucket: aws.String(s3Bucket),
		CreateBucketConfiguration: &types2.CreateBucketConfiguration{
			LocationConstraint: types2.BucketLocationConstraint(region),
		},
	})

	if err != nil {
		return fmt.Errorf("failed to create bucket %s: %v", s3Bucket, err)
	}

	_, err = s3Client.PutBucketTagging(context.TODO(), &s3.PutBucketTaggingInput{
		Bucket: aws.String(s3Bucket),
		Tagging: &types2.Tagging{
			TagSet: []types2.Tag{
				{
					Key:   aws.String("Description"),
					Value: aws.String(description),
				},
			},
		},
	})
	if err != nil {
		return fmt.Errorf("failed to add tags to bucket %s: %v", s3Bucket, err)
	}

	fmt.Printf("Bucket %s created successfully\n", s3Bucket)
	return nil
}

func DeleteObjectFromS3Bucket(sess aws.Config, s3Bucket string, objectToDelete string) error {
	s3Svc := s3.NewFromConfig(sess)

	deleteObjectInput := &s3.DeleteObjectInput{
		Bucket: aws.String(s3Bucket),
		Key:    aws.String(objectToDelete),
	}

	_, err := s3Svc.DeleteObject(context.TODO(), deleteObjectInput)
	if err != nil {
		return fmt.Errorf("failed to delete object %q from bucket %q: %w", objectToDelete, s3Bucket, err)
	}

	fmt.Printf("Successfully deleted object %q from bucket %q\n", objectToDelete, s3Bucket)
	return nil
}

// ExtractOIDCProviderID extracts the OIDC provider from the EKS cluster result (without scheme, eg. no https://).
func ExtractOIDCProviderID(clusterResult *eks.DescribeClusterOutput) (string, error) {
	if clusterResult == nil || clusterResult.Cluster == nil || clusterResult.Cluster.Identity == nil {
		return "", fmt.Errorf("invalid cluster result")
	}

	return strings.ReplaceAll(*clusterResult.Cluster.Identity.Oidc.Issuer, "https://", ""), nil
}
