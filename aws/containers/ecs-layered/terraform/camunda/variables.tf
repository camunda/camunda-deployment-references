variable "prefix" {
  type        = string
  description = "Name prefix of the services and secrets"
}

################################################################
#                  Inputs from the network layer               #
################################################################

variable "vpc_id" {
  type        = string
  description = "Network layer output: ID of the VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Network layer output: private subnet IDs"
}

################################################################
#                  Inputs from the compute layer               #
################################################################

variable "ecs_cluster_id" {
  type        = string
  description = "Compute layer output: ID of the ECS cluster"
}

variable "task_execution_role_arn" {
  type        = string
  description = "Compute layer output: ARN of the task execution role"
}

variable "task_execution_role_name" {
  type        = string
  description = "Compute layer output: name of the task execution role, to attach the secret read policy of this layer"
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Compute layer output: KMS key that encrypts the secrets"
}

variable "registry_credentials_arn" {
  type        = string
  default     = ""
  description = "Compute layer output: registry credentials secret, empty for public images"
}

variable "camunda_ports_security_group_id" {
  type        = string
  description = "Compute layer output: security group that opens the Camunda ports inside the VPC"
}

variable "egress_security_group_id" {
  type        = string
  description = "Compute layer output: security group that allows outbound HTTP and HTTPS"
}

variable "efs_security_group_id" {
  type        = string
  description = "Compute layer output: security group of the EFS file systems"
}

################################################################
#                Inputs from the object storage layer          #
################################################################

variable "backup_bucket_name" {
  type        = string
  description = "Object storage layer output: backup bucket"
}

variable "backup_access_policy_arn" {
  type        = string
  description = "Object storage layer output: policy granting access to the backup bucket"
}

variable "lease_bucket" {
  type = object({
    bucket_name       = string
    access_policy_arn = string
  })
  description = "Object storage layer output lease_buckets[<zone>]: the node ID lease bucket of this zone. One bucket per zone, never shared."
}

################################################################
#                 Inputs from the storage layer                #
################################################################

variable "secondary_storage" {
  type = object({
    type                   = string
    host                   = string
    port                   = number
    database_name          = string
    jdbc_url               = string
    jdbc_driver_class_name = string
    iam_auth_enabled       = bool
  })
  description = "Storage layer output: connection settings of the secondary storage"

  validation {
    condition     = var.secondary_storage.type == "rdbms" && var.secondary_storage.iam_auth_enabled
    error_message = "This layer supports RDBMS secondary storage with IAM authentication."
  }
}

variable "rds_db_connect_policy_arn" {
  type        = string
  description = "Storage layer output rds_db_connect_policy_arns[\"camunda\"]: lets the task role connect as the camunda database user"
}

variable "db_seed_done" {
  type        = string
  default     = ""
  description = "Storage layer output: changes once the database users exist. Only used to order the deployment."
}

################################################################
#                Inputs from the exposure layer                #
################################################################

variable "alb_listener_http_webapp_arn" {
  type        = string
  description = "Exposure layer output: listener the web app rules attach to"
}

variable "alb_listener_http_management_arn" {
  type        = string
  description = "Exposure layer output: listener for the management endpoint"
}

variable "nlb_grpc_arn" {
  type        = string
  description = "Exposure layer output: network load balancer for gRPC"
}

variable "enable_management_endpoint" {
  type        = bool
  default     = false
  description = "Publish the management endpoint (9600) on the load balancer. It is unauthenticated: leave it off and reach it through a jump host or a VPN."
}

################################################################
#                Inputs from the identity layer                #
################################################################

variable "oidc" {
  type = object({
    issuer_uri      = string
    token_uri       = string
    audience        = string
    redirect_uri    = string
    username_claim  = string
    client_id_claim = string
    admin_claim     = string
    orchestration = object({
      client_id         = string
      client_secret_arn = string
    })
    connectors = object({
      client_id         = string
      client_secret_arn = string
      token_scope       = string
    })
  })
  default     = null
  description = "Identity layer output oidc. null selects basic authentication with built-in users."
}

################################################################
#                   Camunda configuration                      #
################################################################

variable "zone" {
  type        = string
  default     = "zone-a"
  description = "Zone of this deployment. The brokers are named <zone>_<index>. Growing to a second region later adds a zone: it does not rename these brokers."
}

variable "zones" {
  type = list(object({
    name               = string
    number_of_brokers  = number
    number_of_replicas = number
    priority           = number
  }))
  default = [
    { name = "zone-a", number_of_brokers = 3, number_of_replicas = 3, priority = 1000 },
  ]
  description = "Every zone of the cluster. List only zones whose brokers run. The replication factor is the sum of number_of_replicas."
}

variable "partition_count" {
  type        = number
  default     = 3
  description = "Number of partitions. It does not change when a zone is added."
}
