locals {
  aurora_cluster_name = "cluster-name-pg-std" # Replace "cluster-name" with your cluster's name

  aurora_master_username = "c8admin" # Aurora admin username
  aurora_master_password = random_password.aurora_admin.result

  # Database names for Camunda components
  camunda_database_identity   = "camunda_identity"   # Name of your camunda database for Identity
  camunda_database_webmodeler = "camunda_webmodeler" # Name of your camunda database for WebModeler

  # Connection configuration
  camunda_identity_db_username   = "identity_db"   # Username for connection to the Identity DB
  camunda_webmodeler_db_username = "webmodeler_db" # Username for connection to the WebModeler DB

  camunda_identity_db_password   = random_password.identity_db.result
  camunda_webmodeler_db_password = random_password.webmodeler_db.result

  db_tags = {} # additional tags that you may want to apply to the resources
}

# Generate random passwords for database credentials
# To retrieve passwords after apply: terraform output -json | jq '.aurora_master_password.value, .camunda_identity_db_password.value, .camunda_webmodeler_db_password.value'
resource "random_password" "aurora_admin" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
}

resource "random_password" "identity_db" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
}

resource "random_password" "webmodeler_db" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
}

module "postgresql" {
  source = "../../../../modules/aurora"
  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  engine_version             = "17.9"
  auto_minor_version_upgrade = false
  cluster_name               = local.aurora_cluster_name
  default_database_name      = local.camunda_database_identity

  # create each AZs
  availability_zones = ["${local.eks_cluster_region}a", "${local.eks_cluster_region}b", "${local.eks_cluster_region}c"]

  username = local.aurora_master_username
  password = local.aurora_master_password

  vpc_id      = module.eks_cluster.vpc_id
  subnet_ids  = module.eks_cluster.private_subnet_ids
  cidr_blocks = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)

  num_instances  = "1" # only one instance, you can add add other read-only instances if you want
  instance_class = "db.t3.medium"

  tags       = local.db_tags
  depends_on = [module.eks_cluster]
}

output "postgres_endpoint" {
  value       = module.postgresql.aurora_endpoint
  description = "The Postgres endpoint URL"
}

output "aurora_master_username" {
  description = "Aurora admin username"
  value       = local.aurora_master_username
}

output "aurora_master_password" {
  description = "Aurora admin password"
  value       = local.aurora_master_password
  sensitive   = true
}

output "camunda_identity_db_password" {
  description = "Identity DB password"
  value       = local.camunda_identity_db_password
  sensitive   = true
}

output "camunda_webmodeler_db_password" {
  description = "WebModeler DB password"
  value       = local.camunda_webmodeler_db_password
  sensitive   = true
}

output "postgres_major_version" {
  description = "PostgreSQL major version (derived from Aurora engine_version)"
  value       = split(".", module.postgresql.aurora_engine_version)[0]
}
