#!/bin/bash

# Replace "my-eks-tf-state" with your unique bucket name
export S3_TF_BUCKET_NAME="my-eks-tf-state"

aws s3api create-bucket --bucket "$S3_TF_BUCKET_NAME" --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"
