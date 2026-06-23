################################
# Infra State Reference       #
################################

variable "infra_state_path" {
  type        = string
  default     = "../infra/terraform.tfstate"
  description = "Path to the infra terraform state file (local backend) or S3 key"
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
