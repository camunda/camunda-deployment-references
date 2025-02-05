variable "cluster_1_region" {
  description = "Region of the cluster 1"
  default     = "us-east-1"
  type        = string
}

variable "cluster_1_vpc_id" {
  description = "VPC ID of the cluster 1"
  type        = string
}

variable "cluster_2_region" {
  description = "Region of the cluster 2"
  default     = "us-east-2"
  type        = string
}

variable "cluster_2_vpc_id" {
  description = "VPC ID of the cluster 2"
  type        = string
}
