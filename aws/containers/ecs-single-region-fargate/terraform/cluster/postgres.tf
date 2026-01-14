
module "postgresql" {
  source = "../../../../modules/aurora"

  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  engine_version             = "17.7"
  auto_minor_version_upgrade = false
  cluster_name               = "${var.prefix}-camunda-db-cluster"
  default_database_name      = var.db_name

  iam_auth_enabled = var.db_iam_auth_enabled

  # create each AZs
  availability_zones = module.vpc.azs

  username = var.db_admin_username
  password = local.db_admin_password_effective

  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnets
  cidr_blocks = [var.cidr_blocks]

  num_instances  = "1" # only one instance, you can add add other read-only instances if you want
  instance_class = "db.t3.medium"
}
