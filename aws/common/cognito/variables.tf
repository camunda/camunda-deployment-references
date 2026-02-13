# Variables for AWS Cognito Test Module

variable "resource_prefix" {
  description = "Prefix for Cognito resources. If empty, uses 'camunda-test'"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Bare hostname for Camunda deployment (e.g., my-cluster.camunda.example.com). No protocol, no trailing slash. Used to construct OIDC callback URLs."
  type        = string
  default     = ""
}

variable "enable_webmodeler" {
  description = "Enable Web Modeler component (creates additional client)"
  type        = bool
  default     = false
}

variable "enable_console" {
  description = "Enable Console component (creates additional client)"
  type        = bool
  default     = false
}

variable "create_test_user" {
  description = "Create a test user for simulating human login"
  type        = bool
  default     = false
}

variable "test_user_name" {
  description = "Email/Username for the test user"
  type        = string
  default     = "camunda-test@example.com"
}

variable "test_user_password" {
  description = "Password for the test user (must meet Cognito password policy)"
  type        = string
  default     = "CamundaTest123!"
  sensitive   = true
}

variable "mfa_enabled" {
  description = "Enable MFA for Cognito users (OPTIONAL mode)"
  type        = bool
  default     = false
}

variable "auto_cleanup_hours" {
  description = "Hours after which this Cognito pool should be automatically cleaned up (for CI tracking)"
  type        = number
  default     = 72 # 3 days
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
