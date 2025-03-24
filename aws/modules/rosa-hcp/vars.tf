
variable "cluster_name" {
  type        = string
  description = "The name of the ROSA cluster to create"
  default     = "my-ocp-cluster"
}

variable "openshift_version" {
  type        = string
  description = "The version of ROSA to be deployed"
  # renovate: datasource=custom.rosa-camunda depName=red-hat-openshift versioning=semver
  default = "4.18.4"
  validation {
    condition     = can(regex("^[0-9]*[0-9]+.[0-9]*[0-9]+.[0-9]*[0-9]+$", var.openshift_version))
    error_message = "openshift_version must be with structure <major>.<minor>.<patch> (for example 4.13.6)."
  }
}

variable "replicas" {
  type        = string
  description = "The number of computer nodes to create. Must be a minimum of 2 for a single-AZ cluster, 3 for multi-AZ."
  default     = "2"
}

variable "private" {
  type        = bool
  description = "Restrict master API endpoint and application routes to direct, private connectivity."
  default     = false
}

variable "compute_node_instance_type" {
  type        = string
  description = "The EC2 instance type to use for compute nodes"
  default     = "m7i.xlarge"
}

variable "host_prefix" {
  type        = string
  description = "The subnet mask to assign to each compute node in the cluster"
  default     = "23"
}

variable "availability_zones_count" {
  type        = number
  description = "The count of availability (minimum 2) zones to utilize within the specified AWS Region, where pairs of public and private subnets will be generated. Valid only when availability_zones variable is not provided. This value should not be updated, please create a new resource instead."
  default     = 2
}

variable "availability_zones" {
  type        = list(string)
  description = "A list of availability zone names in the region. By default, this is set to `null` and is not used; instead, `availability_zones_count` manages the number of availability zones. This value should not be updated directly. To make changes, please create a new resource."
  default     = null
}


variable "aws_availability_zones" {
  type        = list(string)
  description = "The AWS availability zones where instances of the default worker machine pool are deployed. Leave empty for the installer to pick availability zones from the VPC `availability_zones` or `availability_zones_count`"
  default     = []
}

variable "vpc_cidr_block" {
  type        = string
  description = "value of the CIDR block to use for the VPC"
  default     = "10.0.0.0/16"
}

variable "machine_cidr_block" {
  type        = string
  description = "value of the CIDR block to use for the machine"
  default     = "10.0.0.0/18"
}

variable "service_cidr_block" {
  type        = string
  description = "value of the CIDR block to use for the services"
  default     = "10.0.128.0/18"
}
variable "pod_cidr_block" {
  type        = string
  description = "value of the CIDR block to use for the pods"
  default     = "10.0.64.0/18"
}

variable "htpasswd_username" {
  type        = string
  description = "htpasswd username"
  default     = "kubeadmin"
}

variable "htpasswd_password" {
  type        = string
  description = "htpasswd password"
  sensitive   = true
}
