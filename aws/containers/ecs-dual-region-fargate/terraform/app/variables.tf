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
  type        = string
  default     = "camunda/camunda:8.9.0"
  description = "Container image for the Camunda orchestration cluster tasks (Zeebe broker + gateway + webapps)"
}

variable "connectors_image" {
  type        = string
  default     = "camunda/connectors-bundle:8.10.0-alpha2"
  description = "Container image for the Camunda connectors-bundle tasks. Separate from camunda_image because connectors ship as a distinct artifact from the orchestration cluster."
}
