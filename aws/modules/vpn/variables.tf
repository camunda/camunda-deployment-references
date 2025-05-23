variable "vpc_id" {
  type        = string
  description = "VPC ID to access from the VPN"
}

variable "vpn_client_cidr" {
  type        = string
  default     = "172.0.0.0/22"
  description = "Client CIDR, it must be different from the primary VPC CIDR"
}

variable "vpn_allowed_cidr_blocks" {
  description = "List of CIDR blocks that are allowed to access the Client VPN endpoint on UDP port 443. Use caution when allowing wide access (e.g., 0.0.0.0/0)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vpn_split_tunnel" {
  default     = true
  description = "When you have a Client VPN endpoint, all traffic from clients is routed over the Client VPN tunnel if set to false. When you enable split-tunnel on the Client VPN endpoint, we push the routes on the Client VPN endpoint route table to the device that is connected to the Client VPN endpoint. This ensures that only traffic with a destination to the network matching a route from the Client VPN endpoint route table is routed over the Client VPN tunnel."
}

variable "vpc_subnet_ids" {
  type        = set(string)
  description = "List of subnets to access"
}

variable "vpc_target_network_cidr" {
  type        = string
  description = "CIDR of the target network to access"
}

variable "vpn_name" {
  type        = string
  description = "Name of the VPN"
}

variable "vpn_endpoint_dns_servers" {
  type        = list(string)
  default     = ["169.254.169.253"]
  description = "List of DNS Servers for the VPN, defaults on the one of the VPC (see https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html)"
}

variable "vpn_cloudwatch_log_group_retention" {
  type        = number
  default     = 365
  description = "Number of days of retention to keep vpn logs"
}

variable "vpn_session_timeout_hours" {
  type        = number
  default     = 8
  description = "Number of hours to timeout a session of the VPN connection"
}

variable "vpn_client_banner" {
  description = "Banner to display to the users of the VPN"
  type        = string
  default     = "This VPN is for authorized users only. All activities may be monitored and recorded."
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
  default     = 2048
  description = "Key size in bits for the CA private key"
}

variable "ca_common_name" {
  type        = string
  default     = "common.local"
  description = "Common Name (CN) field for the CA certificate"
}
variable "server_common_name" {
  type        = string
  default     = "server.common.local"
  description = "Common Name (CN) field for the server certificate"
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

variable "key_algorithm" {
  type        = string
  default     = "RSA"
  description = "Algorithm used to generate private keys (client, server)"
}

variable "key_bits" {
  type        = number
  default     = 2048
  description = "Key size in bits for private keys (client, server)"
}

variable "client_certificate_validity_period_hours" {
  type        = number
  default     = 8760
  description = "Validity period of client certificates in hours (default: 1 year)"
}
variable "server_certificate_validity_period_hours" {
  type        = number
  default     = 8760
  description = "Validity period of server certificates in hours (default: 1 year)"
}
