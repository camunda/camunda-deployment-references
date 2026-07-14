################################
# Region Configuration        #
################################

variable "region_0" {
  type        = string
  default     = "eu-west-2"
  description = "AWS region for the primary (owner) cluster (must match infra/ and vpc/ configuration)"
}

variable "region_1" {
  type        = string
  default     = "eu-west-3"
  description = "AWS region for the secondary (accepter) cluster (must match infra/ and vpc/ configuration)"
}

################################
# Infra State Reference       #
################################

variable "terraform_backend_bucket" {
  type        = string
  description = "S3 bucket name storing Terraform state for all layers"
}

variable "terraform_backend_region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region of the S3 bucket storing Terraform state (may differ from the deployment regions)"
}

variable "terraform_backend_key_prefix" {
  type        = string
  description = "S3 key prefix shared by all layers. E.g. 'aws/containers/ecs-dual-region-fargate/my-cluster/' yields 's3://<bucket>/<prefix>infra/terraform.tfstate'"
}

################################
# App Variables               #
################################

variable "aws_profile" {
  type        = string
  description = "AWS Profile to use (null = use default credential chain)"
  default     = null
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}

variable "camunda_image" {
  type = string
  # Dual-region requires the SNAPSHOT build: zone-aware partition distribution
  # (cross-region "region awareness") is only available there and ships in the
  # 8.10 alpha3 image. Keep SNAPSHOT until then; the trailing marker tells the
  # alpha-availability check to skip this line (see internal_global_alpha_availability_check.yml).
  # TODO: [release-duty] at 8.10 alpha3, bump to the published alpha image tag
  # and remove the "alpha-availability-check:ignore" markers in this file.
  default     = "camunda/camunda:8.10-SNAPSHOT" # alpha-availability-check:ignore
  description = "Container image for the Camunda orchestration cluster tasks (Zeebe broker + gateway + webapps)"
}

variable "connectors_image" {
  type = string
  # Pinned to SNAPSHOT for the same reason as camunda_image above (dual-region
  # region awareness ships in 8.10 alpha3).
  # TODO: [release-duty] at 8.10 alpha3, bump to the published alpha image tag
  # and remove the "alpha-availability-check:ignore" marker.
  default     = "camunda/connectors-bundle:8.10-SNAPSHOT" # alpha-availability-check:ignore
  description = "Container image for the Camunda connectors-bundle tasks. Separate from camunda_image because connectors ship as a distinct artifact from the orchestration cluster."
}
