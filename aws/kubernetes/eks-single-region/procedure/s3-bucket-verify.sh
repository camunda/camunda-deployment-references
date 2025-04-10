#!/bin/bash

aws s3api get-bucket-versioning --bucket "$S3_TF_BUCKET_NAME" --region "$AWS_REGION"
