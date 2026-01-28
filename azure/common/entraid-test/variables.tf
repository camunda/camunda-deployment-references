variable "resource_prefix" {
  description = "Prefix for EntraID resources. If empty, uses 'camunda-test'"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for Camunda deployment (e.g., camunda.example.com)"
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Azure AD Tenant ID (optional, will use current context if not provided)"
  type        = string
  default     = ""
}

variable "enable_webmodeler" {
  description = "Enable Web Modeler component (creates additional client secret)"
  type        = bool
  default     = false
}

variable "create_test_user" {
  description = "Create a test user for simulating human login (requires User.ReadWrite.All permission)"
  type        = bool
  default     = false
}

variable "test_user_name" {
  description = "Username for the test user (will be used as email prefix)"
  type        = string
  default     = "camunda-test"
}

variable "test_user_password" {
  description = "Password for the test user"
  type        = string
  default     = "CamundaTest123!"
  sensitive   = true
}

variable "secret_validity_hours" {
  description = "Validity period for client secrets in hours (default: 720h = 30 days)"
  type        = number
  default     = 720

  validation {
    condition     = var.secret_validity_hours >= 1 && var.secret_validity_hours <= 17520 # max 2 years
    error_message = "Secret validity must be between 1 hour and 17520 hours (2 years)."
  }
}

variable "auto_cleanup_hours" {
  description = "Hours after which this EntraID app should be automatically cleaned up (for CI tracking)"
  type        = number
  default     = 72 # 3 days
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
