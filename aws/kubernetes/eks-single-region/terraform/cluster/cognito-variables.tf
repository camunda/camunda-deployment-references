# Cognito Variables for Camunda Platform on AWS EKS

variable "enable_cognito" {
  description = "Enable Amazon Cognito as the identity provider instead of Keycloak"
  type        = bool
  default     = false
}

variable "cognito_resource_prefix" {
  description = "Prefix for Cognito resource names. If empty, uses the EKS cluster name"
  type        = string
  default     = ""
}

variable "cognito_mfa_enabled" {
  description = "Enable MFA for Cognito users (OPTIONAL mode)"
  type        = bool
  default     = false
}

variable "cognito_create_admin_user" {
  description = "Create an initial admin user in Cognito"
  type        = bool
  default     = true
}

variable "cognito_admin_temporary_password" {
  description = "Temporary password for the initial admin user (must be changed on first login)"
  type        = string
  default     = "TempP@ssw0rd123!"
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for Camunda deployment (e.g., camunda.example.com)"
  type        = string
  default     = ""
}

variable "identity_initial_user_email" {
  description = "Email address for the initial admin user"
  type        = string
  default     = "admin@camunda.local"
}

variable "enable_console" {
  description = "Enable Camunda Console component"
  type        = bool
  default     = false
}

variable "enable_webmodeler" {
  description = "Enable Web Modeler component"
  type        = bool
  default     = false
}
