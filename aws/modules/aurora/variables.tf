# ! Developer: if you are adding a variable without a default value, please ensure to reference it in the cleanup script (.github/actions/eks-cleanup-resources/scripts/destroy.sh)
variable "cluster_name" {
  description = "Name of the cluster, also used to prefix dependent resources. Format: /[[:lower:][:digit:]-]/"
}

variable "engine" {
  default     = "aurora-postgresql"
  description = "The engine type e.g. aurora, aurora-mysql, aurora-postgresql, ..."
}

variable "engine_version" {
  type = string
  # renovate: datasource=endoflife-date depName=amazon-rds-postgresql versioning=semver
  default     = "15.4"
  description = "The DB engine version for Postgres to use."
}

variable "auto_minor_version_upgrade" {
  default     = true
  description = "If true, minor engine upgrades will be applied automatically to the DB instance during the maintenance window"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  description = "Array of availability zones to use for the Aurora cluster"
}

variable "instance_class" {
  default     = "db.t3.medium"
  description = "The instance type of the Aurora instances"
}

variable "num_instances" {
  default     = "1"
  description = "Number of instances"
}

variable "username" {
  type        = string
  description = "The username for the postgres admin user. Important: secret value!"
  sensitive   = true
}

variable "password" {
  type        = string
  description = "The password for the postgres admin user. Important: secret value!"
  sensitive   = true
}

variable "tags" {
  default     = {}
  description = "Additional tags to add to the resources"
}

variable "subnet_ids" {
  type        = list(string)
  description = "The subnet IDs to create the cluster in. For easier usage we are passing through the subnet IDs from the AWS EKS Cluster module."
}

variable "cidr_blocks" {
  type        = list(string)
  description = "The CIDR blocks to allow acces from and to."
}

# pass through from root
variable "vpc_id" {
  description = "The VPC ID to create the cluster in. For easier usage we are passing through the VPC ID from the AWS EKS Cluster module."
}

# Allows adding additional iam roles to grant access from Aurora to e.g. S3
variable "iam_roles" {
  type        = list(string)
  default     = []
  description = "Allows propagating additional IAM roles to the Aurora cluster to allow e.g. access to S3"
}

# Allows defining whether IAM auth should be activated for IRSA usage
variable "iam_auth_enabled" {
  default     = false
  type        = bool
  description = "Determines whether IAM auth should be activated for IRSA usage"
}

variable "ca_cert_identifier" {
  default     = "rds-ca-rsa2048-g1"
  type        = string
  description = "Specifies the identifier of the CA certificate for the DB instance"
}

variable "default_database_name" {
  type        = string
  default     = "camunda"
  description = "The name for the automatically created database on cluster creation."
}

variable "iam_roles_with_policies" {
  description = "List of roles with their trust and access policies"
  type = list(object({
    # Name of the Role to create
    role_name = string

    # Assume role trust policy for this Aurora role as a json string
    trust_policy = string

    # Access policy for Aurora allowing access as a json string
    # see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html
    # Since the DbiResourceId may be unknown during the apply process, and because each instance of the RDS cluster contains its own DbiResourceId,
    # we use the wildcard `dbuser:*` to apply to all database instances.
    # Example:
    #   [
    #     {
    #     role_name      = "AuroraRole"
    #     trust_policy   =
    #           {
    #             "Version": "2012-10-17",
    #             "Statement": [
    #               {
    #                 "Effect": "Allow",
    #                 "Principal": {
    #                   "Federated": "arn:aws:iam::<YOUR-ACCOUNT-ID>:oidc-provider/oidc.eks.<YOUR-REGION>.amazonaws.com/id/<YOUR-OIDC-ID>"
    #                 },
    #                 "Action": "sts:AssumeRoleWithWebIdentity",
    #                 "Condition": {
    #                   "StringEquals": {
    #                     "oidc.eks.<YOUR-REGION>.amazonaws.com/id/<YOUR-OIDC-PROVIDER-ID>:sub": "system:serviceaccount:<YOUR-NAMESPACE>:<YOUR-SA-NAME>"
    #                   }
    #                 }
    #               }
    #             ]
    #           }
    #
    #     access_policy  =
    #             {
    #               "Version": "2012-10-17",
    #               "Statement": [
    #                 {
    #                   "Effect": "Allow",
    #                   "Action": [
    #                     "rds-db:connect"
    #                   ],
    #                   "Resource": "arn:aws:rds-db:<YOUR-REGION>:<YOUR-ACCOUNT-ID>:dbuser:*/<YOUR-DB-USER-NAME>"
    #                 }
    #               ]
    #             }
    #
    #   }
    #   ]
    access_policy = string
  }))

  # By default, don't create any role and associated policies.
  default = []
}
