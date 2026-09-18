################################################################
#                        Global Options                        #
################################################################

variable "prefix" {
  type        = string
  description = "The prefix to use for names of resources"
  default     = "camunda"
}

variable "registry_username" {
  type        = string
  description = "(Optional) The username for the container registry (e.g., Docker Hub)"
  default     = ""
}

variable "registry_password" {
  type        = string
  description = "(Optional) The password for the container registry (e.g., Docker Hub)"
  default     = ""
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}

################################################################
#                       Network Options                        #
################################################################

variable "cidr_blocks" {
  type        = string
  default     = "10.190.0.0/16"
  description = "The CIDR block to use for the VPC"
}

################################################################
#                      Security Options                        #
################################################################

variable "limit_access_to_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer"
}

variable "ports" {
  type = map(number)
  default = {
    postgresql                            = 5432
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
    management_identity_app               = 8084
    management_identity_management        = 8082
    keycloak_http                         = 18080
    keycloak_management                   = 9000
    camunda_hub_restapi                   = 8081
    camunda_hub_management                = 8091
    camunda_hub_websockets                = 8060
  }
  description = "The ports to open for the security groups within the VPC"
}

################################################################
#                     Database / IAM Options                    #
################################################################

variable "db_name" {
  type        = string
  description = "Database name used by Camunda components"
  default     = "camunda"

  validation {
    # Interpolated into the DB seed SQL (postgres_seed.tf) as a quoted identifier
    # and in the `dbname=` conninfo string; restrict to a safe PostgreSQL
    # identifier so quotes/whitespace cannot break SQL or inject.
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.db_name)) && length(var.db_name) <= 63
    error_message = "db_name must be a valid PostgreSQL identifier: start with a letter or underscore, contain only letters/digits/underscores, and be at most 63 characters."
  }
}

variable "db_admin_username" {
  type        = string
  description = "Admin username for the Aurora PostgreSQL cluster (demo default; use Secrets Manager in production)"
  default     = "camunda_admin"
  sensitive   = true
}

variable "db_admin_password" {
  type        = string
  description = "Optional override for the Aurora PostgreSQL admin password. If empty, a random password is generated and stored in Secrets Manager."
  default     = ""
  sensitive   = true
}

variable "db_iam_auth_enabled" {
  type        = bool
  description = "Enable IAM database authentication on the Aurora cluster. Required: every component's datasource uses the AWS JDBC wrapper with wrapperPlugins=iam, so a precondition rejects false (see postgres_seed.tf)."
  default     = true
}

variable "db_seed_enabled" {
  type        = bool
  description = "Run the one-time ECS task that provisions every component's database role and dedicated database and grants them rds_iam (connecting as db_admin_username). This task is the only thing that creates them, so on a cluster that has never been seeded, turning it off leaves the orchestration cluster, Management Identity and Camunda Hub unable to connect at startup. Safe to turn off only when those roles, databases and grants already exist, which Terraform cannot verify -- hence no precondition on it."
  default     = true
}

variable "db_seed_iam_usernames" {
  type        = list(string)
  description = "Database users to create and grant rds_iam + privileges for (used for IAM DB auth)"
  default     = ["camunda"]

  validation {
    # Each element is interpolated into the seed SQL (postgres_seed.tf) both as a
    # single-quoted literal in the rolname predicate and as a quoted identifier, and is
    # iterated over by a shell loop in the same task. Restrict to a safe PostgreSQL
    # identifier so a quote or whitespace cannot break the SQL or the loop. Same guard
    # as db_name, identity_db_* and keycloak_db_* below.
    condition = alltrue([
      for user in var.db_seed_iam_usernames :
      can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", user)) && length(user) <= 63
    ])
    error_message = "Every db_seed_iam_usernames entry must be a valid PostgreSQL identifier: start with a letter or underscore, contain only letters/digits/underscores, and be at most 63 characters."
  }
}

variable "identity_db_name" {
  type        = string
  description = "Dedicated database name for Management Identity on the shared Aurora cluster"
  default     = "identity"

  validation {
    # Interpolated into the DB seed SQL (postgres_seed.tf); restrict to a safe
    # PostgreSQL identifier so quotes/whitespace cannot break SQL or inject.
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.identity_db_name)) && length(var.identity_db_name) <= 63
    error_message = "identity_db_name must be a valid PostgreSQL identifier: start with a letter or underscore, contain only letters/digits/underscores, and be at most 63 characters."
  }
}

variable "identity_db_username" {
  type        = string
  description = "Database role for Management Identity. Authenticates with an IAM token (the image ships the AWS Advanced JDBC wrapper); the role also carries a password, used only to bootstrap it in the DB seed."
  default     = "identity"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.identity_db_username)) && length(var.identity_db_username) <= 63
    error_message = "identity_db_username must be a valid PostgreSQL identifier: start with a letter or underscore, contain only letters/digits/underscores, and be at most 63 characters."
  }
}

variable "camunda_hub_db_name" {
  type        = string
  description = "Dedicated database name for Camunda Hub on the shared Aurora cluster"
  default     = "camunda-hub"

  validation {
    # Hyphens are allowed here (unlike the neighbours) because the default is the
    # app-conventional "camunda-hub"; every use quotes the identifier, in the seed SQL
    # and in the JDBC URL alike.
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_-]*$", var.camunda_hub_db_name)) && length(var.camunda_hub_db_name) <= 63
    error_message = "camunda_hub_db_name must be a valid PostgreSQL identifier: start with a letter or underscore, contain only letters/digits/underscores/hyphens, and be at most 63 characters."
  }
}

variable "camunda_hub_db_username" {
  type        = string
  description = "Database role for Camunda Hub. Authenticates with an IAM token via the AWS Advanced JDBC wrapper, so it carries no password."
  default     = "camunda-hub"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_-]*$", var.camunda_hub_db_username)) && length(var.camunda_hub_db_username) <= 63
    error_message = "camunda_hub_db_username must be a valid PostgreSQL identifier: start with a letter or underscore, contain only letters/digits/underscores/hyphens, and be at most 63 characters."
  }
}

variable "keycloak_db_name" {
  type        = string
  description = "Dedicated database name for Keycloak on the shared Aurora cluster"
  default     = "keycloak"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.keycloak_db_name)) && length(var.keycloak_db_name) <= 63
    error_message = "keycloak_db_name must be a valid PostgreSQL identifier: start with a letter or underscore, contain only letters/digits/underscores, and be at most 63 characters."
  }
}

variable "keycloak_db_username" {
  type        = string
  description = "Password-authenticated database role for Keycloak"
  default     = "keycloak"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.keycloak_db_username)) && length(var.keycloak_db_username) <= 63
    error_message = "keycloak_db_username must be a valid PostgreSQL identifier: start with a letter or underscore, contain only letters/digits/underscores, and be at most 63 characters."
  }
}

variable "keycloak_admin_username" {
  type        = string
  description = "Keycloak bootstrap admin username"
  default     = "admin"

  validation {
    # Not interpolated into SQL, but kept consistent with the DB-role identifiers
    # above so the bootstrap admin username stays a predictable, quote-free token.
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.keycloak_admin_username)) && length(var.keycloak_admin_username) <= 63
    error_message = "keycloak_admin_username must be a valid identifier: start with a letter or underscore, contain only letters/digits/underscores, and be at most 63 characters."
  }
}

################################################################
#                         KMS Options                          #
################################################################

variable "secrets_kms_key_arn" {
  description = "Optional existing KMS key ARN to use for encrypting Secrets Manager secrets. If empty, this stack will create and manage a CMK."
  type        = string
  default     = ""
}

################################################################
#                     ALB TLS (HTTPS) — opt-in                 #
################################################################

variable "alb_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the shared ALB. When set, an HTTPS :443 listener is created, all web-app/OIDC traffic is served over TLS (and HTTP :80 redirects to it), and Keycloak trusts the ALB's X-Forwarded-Proto so the realm needs no sslRequired relaxation. Empty (default) keeps this reference on plain HTTP :80 for the demo."
  default     = ""
}

variable "alb_ssl_policy" {
  type        = string
  description = "SSL negotiation policy for the HTTPS ALB listener (used only when alb_certificate_arn is set)."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

################################################################
#                        Camunda Hub                           #
################################################################

variable "enable_camunda_hub" {
  type        = bool
  description = "Deploy the Camunda Hub (Web Modeler) ECS task. Requires authentication_mode = \"oidc\"; enabling it also registers the web-modeler client in the bundled Keycloak realm."
  default     = false
}

variable "camunda_license_key" {
  type        = string
  description = "(Optional) Camunda license key. When set (and enable_camunda_hub = true) it is stored in Secrets Manager and injected as CAMUNDA_LICENSE_KEY. Leave empty to run Camunda Hub in its trial mode (fine for tests)."
  default     = ""
  sensitive   = true
}

variable "camunda_hub_restapi_image" {
  type        = string
  description = "Container image for the Camunda Hub REST API + web UI. Registry credentials are only attached when this points at registry.camunda.cloud (private); public Docker Hub images pull without credentials."
  # TODO: [release-duty] before the release, update the below versions to the stable release!
  # TODO: [release-duty] adjust renovate comment to bump the minor version to the new stable release
  # TODO: [release-duty] remove the alpha suffix from the regex for stable versions
  # renovate: datasource=docker depName=camunda/hub versioning=regex:^8\.10(?:\.(?<patch>\d+))?(?:-alpha(?<prerelease>\d+))?$
  default = "camunda/hub:8.10.0-alpha5"
}

variable "camunda_hub_websockets_image" {
  type        = string
  description = "Container image for the Camunda Hub websockets relay. Registry credentials are only attached when this (or the restapi image) points at registry.camunda.cloud (private)."
  # TODO: [release-duty] before the release, update the below versions to the stable release!
  # TODO: [release-duty] adjust renovate comment to bump the minor version to the new stable release
  # TODO: [release-duty] remove the alpha suffix from the regex for stable versions
  # renovate: datasource=docker depName=camunda/hub-websockets versioning=regex:^8\.10(?:\.(?<patch>\d+))?(?:-alpha(?<prerelease>\d+))?$
  default = "camunda/hub-websockets:8.10.0-alpha5"
}

################################################################
#                      Load test Options                       #
################################################################

variable "enable_load_tests" {
  description = "Deploy the load test overlay: a long-lived Prometheus that discovers this cluster through Cloud Map, and a load generator driving process instances at it. Off by default; the plan is unchanged while it is false."
  type        = bool
  default     = false
}

variable "load_tests_prometheus_port" {
  description = "Port the load test Prometheus listens on. Deliberately outside var.ports so enabling the overlay does not widen the cluster's own security group."
  type        = number
  default     = 9090
}

variable "load_tests_retention_time" {
  description = "How long the load test Prometheus keeps samples, as a Prometheus duration."
  type        = string
  default     = "168h"
}

variable "load_tests_start_rate" {
  description = "Process instances started per second by the load generator."
  type        = number
  default     = 10
}
