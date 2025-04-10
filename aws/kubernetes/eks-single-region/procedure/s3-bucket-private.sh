#!/bin/bash

aws s3api put-public-access-block --bucket "$S3_TF_BUCKET_NAME" --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" --region "$AWS_REGION"
