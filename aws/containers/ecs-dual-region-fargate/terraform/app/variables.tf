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
  description = "Container image for Camunda orchestration and connectors tasks"
}
