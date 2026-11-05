variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

variable "authentication_mode" {
  type        = string
  default     = "basic"
  description = "basic: built-in users, no identity provider. oidc: your OIDC provider, described by external_oidc."

  validation {
    condition     = contains(["basic", "oidc"], var.authentication_mode)
    error_message = "authentication_mode must be basic or oidc."
  }
}

variable "external_oidc" {
  type = object({
    issuer_uri             = string
    token_uri              = string
    orchestration_audience = string

    orchestration_client_id         = string
    orchestration_client_secret_arn = string
    connectors_client_id            = string
    connectors_client_secret_arn    = string

    # Claim names. The defaults are the most common claim names; Entra ID, for one, identifies the
    # calling application with azp or appid instead of client_id.
    username_claim  = optional(string, "preferred_username")
    client_id_claim = optional(string, "client_id")

    # Scope for the connectors client-credentials request. Entra ID v2 needs <resource>/.default.
    connectors_token_scope = optional(string, "")

    # KMS key the client secrets are encrypted with, when it is not the key of the compute layer
    # (for example when an OIDC provider of the management plane created them). Empty uses the key of
    # the compute layer.
    client_secrets_kms_key_arn = optional(string, "")
  })
  default     = null
  description = "Your OIDC provider. Required when authentication_mode = oidc. Client secrets are existing Secrets Manager ARNs, never raw values, and must be encrypted with the AWS managed key or with the secrets_kms_key_arn of the compute layer, otherwise the task cannot decrypt them."
}

variable "admin_claim_value" {
  type        = string
  default     = "admin"
  description = "Value of the username claim that identifies the administrator. Set it to a principal that exists in your directory, otherwise nobody gets the admin role."

  validation {
    condition     = trimspace(var.admin_claim_value) != ""
    error_message = "admin_claim_value must not be empty: it grants the admin role."
  }
}

variable "public_base_url" {
  type        = string
  default     = ""
  description = "Exposure layer output: browser-facing base URL. The OIDC redirect URI (<base>/sso-callback) is built from it. Required when authentication_mode = oidc."
}

variable "task_execution_role_name" {
  type        = string
  default     = ""
  description = "Compute layer output: execution role that reads the client secrets. Required when authentication_mode = oidc."
}

variable "secrets_kms_key_arn" {
  type        = string
  default     = ""
  description = "Compute layer output: KMS key the client secrets are encrypted with. Required when authentication_mode = oidc."
}
