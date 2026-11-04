mock_provider "aws" {}

variables {
  bucket_name = "test-bucket"
  aws_region  = "eu-west-1"
}

run "backup_is_versioned" {
  command = plan

  variables {
    purpose = "backup"
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 1
    error_message = "backup buckets must be versioned"
  }
}

run "lease_is_not_versioned" {
  command = plan

  variables {
    purpose = "node-id-lease"
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 0
    error_message = "lease buckets must not be versioned"
  }
}

run "existing_kms_key_is_used" {
  command = plan

  variables {
    purpose     = "backup"
    kms_key_arn = "arn:aws:kms:eu-west-1:111111111111:key/abc"
  }

  assert {
    condition     = length(aws_kms_key.this) == 0 && output.kms_key_arn == "arn:aws:kms:eu-west-1:111111111111:key/abc"
    error_message = "no key must be created when one is supplied"
  }
}

run "unknown_purpose_rejected" {
  command = plan

  variables {
    purpose = "logs"
  }

  expect_failures = [var.purpose]
}
