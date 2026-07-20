# use this file for vars without default values
# for the golden file generation

aws_profile = null # uses default AWS credential chain (env vars, default profile, instance profile)

# The app state normally reads the sibling infra state over an S3 backend. For
# golden generation that read is neutralised by test/fixtures/golden/fixture_infra_override.tf
# (a static snapshot of the infra outputs), so these backend coordinates are
# never actually contacted — they only satisfy the required-variable check.
terraform_backend_bucket     = "golden-not-used"
terraform_backend_key_prefix = "golden-not-used/"
