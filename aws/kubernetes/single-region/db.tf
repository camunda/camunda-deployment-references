locals {
  aurora_cluster_name = "cluster-name-pg-std" # Replace "cluster-name" with your cluster's name

  aurora_master_username = "secret_user"    # Replace with your Aurora username
  aurora_master_password = "secretvalue%23" # Replace with your Aurora password, password must contain at least one letter, one number, and one special character.

  camunda_database_keycloak   = "camunda_keycloak"   # Name of your camunda database for Keycloak
  camunda_database_identity   = "camunda_identity"   # Name of your camunda database for Identity
  camunda_database_webmodeler = "camunda_webmodeler" # Name of your camunda database for WebModeler

  # Connection configuration
  camunda_keycloak_db_username   = "keycloak_db"   # This is the username that will be used for connection to the DB on Keycloak db
  camunda_identity_db_username   = "identity_db"   # This is the username that will be used for connection to the DB on Identity db
  camunda_webmodeler_db_username = "webmodeler_db" # This is the username that will be used for connection to the DB on WebModeler db

  camunda_keycloak_db_password   = "secretvalue%24" # Replace with a password that will be used for connection to the DB on Keycloak db
  camunda_identity_db_password   = "secretvalue%25" # Replace with a password that will be used for connection to the DB on Identity db
  camunda_webmodeler_db_password = "secretvalue%26" # Replace with a password that will be used for connection to the DB on WebModeler db
}

module "postgresql" {
  source                     = "git::https://github.com/camunda/camunda-tf-eks-module//modules/aurora?ref=3.1.3"
  engine_version             = "15.8"
  auto_minor_version_upgrade = false
  cluster_name               = local.aurora_cluster_name
  default_database_name      = local.camunda_database_keycloak

  # create each AZs
  availability_zones = ["${local.eks_cluster_region}a", "${local.eks_cluster_region}b", "${local.eks_cluster_region}c"]

  username = local.aurora_master_username
  password = local.aurora_master_password

  vpc_id      = module.eks_cluster.vpc_id
  subnet_ids  = module.eks_cluster.private_subnet_ids
  cidr_blocks = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)

  num_instances  = "1" # only one instance, you can add add other read-only instances if you want
  instance_class = "db.t3.medium"

  depends_on = [module.eks_cluster]
}

output "postgres_endpoint" {
  value       = module.postgresql.aurora_endpoint
  description = "The Postgres endpoint URL"
}
