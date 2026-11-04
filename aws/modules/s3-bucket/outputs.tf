output "bucket_name" {
  value       = aws_s3_bucket.this.id
  description = "Name of the bucket"
}

output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "ARN of the bucket"
}

output "kms_key_arn" {
  value       = local.kms_key_arn
  description = "ARN of the KMS key that encrypts the bucket"
}

output "access_policy_arn" {
  value       = aws_iam_policy.access.arn
  description = "ARN of the IAM policy granting read/write access to the bucket and its key; attach it to the ECS task role"
}
