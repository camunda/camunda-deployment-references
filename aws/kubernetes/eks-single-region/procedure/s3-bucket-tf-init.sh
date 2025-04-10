#!/bin/bash

export S3_TF_BUCKET_KEY="camunda-terraform/terraform.tfstate"

echo "Storing terraform state in s3://$S3_TF_BUCKET_NAME/$S3_TF_BUCKET_KEY"

terraform init -backend-config="bucket=$S3_TF_BUCKET_NAME" -backend-config="key=$S3_TF_BUCKET_KEY"
