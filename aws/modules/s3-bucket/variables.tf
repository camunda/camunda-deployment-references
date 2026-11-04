variable "bucket_name" {
  type        = string
  description = "Name of the bucket. Must be globally unique."
}

variable "purpose" {
  type        = string
  description = "What the bucket stores. backup: Camunda backups (versioned). node-id-lease: Orchestration Cluster node ID leases (not versioned, one bucket per zone, never shared between zones or clusters)."

  validation {
    condition     = contains(["backup", "node-id-lease"], var.purpose)
    error_message = "purpose must be \"backup\" or \"node-id-lease\"."
  }
}

variable "aws_region" {
  type        = string
  description = "Region of the bucket. The access policy denies S3 calls to other regions."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Delete the bucket even if it contains objects. Dev and test only."
}

variable "kms_key_arn" {
  type        = string
  default     = ""
  description = "Existing KMS key to encrypt the bucket with. When empty, the module creates one."
}
