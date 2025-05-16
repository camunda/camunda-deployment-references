variable "s3_bucket_name" {
  type        = string
  description = "Name of the bucket that stores the certificates and keys"
}

variable "s3_ca_directory" {
  type        = string
  default     = "my-ca"
  description = "Directory name inside the S3 bucket where CA and certificates are stored"
}

variable "client_key_names" {
  description = "List of client key names to generate certificates for"
  type        = list(string)
}

variable "kms_key_name" {
  type        = string
  default     = "vpn-certs-kms-key"
  description = "Name of the KMS key used for encrypting certificates and keys in S3"
}

variable "ca_key_algorithm" {
  type        = string
  default     = "RSA"
  description = "Algorithm used to generate the CA private key"
}

variable "ca_key_bits" {
  type        = number
  default     = 4096
  description = "Key size in bits for the CA private key"
}

variable "ca_common_name" {
  type        = string
  default     = "Local CA VPN"
  description = "Common Name (CN) field for the CA certificate"
}

variable "ca_organization" {
  type        = string
  default     = "Organization CA VPN"
  description = "Organization name for the CA certificate"
}

variable "ca_validity_period_hours" {
  type        = number
  default     = 87600
  description = "Validity period of the CA certificate in hours (default: 10 years)"
}

variable "ca_early_renewal_hours" {
  type        = number
  default     = 720
  description = "Time before CA certificate expiration to renew it, in hours (default: 30 days)"
}

variable "client_key_algorithm" {
  type        = string
  default     = "RSA"
  description = "Algorithm used to generate client private keys"
}

variable "client_key_bits" {
  type        = number
  default     = 4096
  description = "Key size in bits for client private keys"
}

variable "client_certificate_validity_period_hours" {
  type        = number
  default     = 8760
  description = "Validity period of client certificates in hours (default: 1 year)"
}
