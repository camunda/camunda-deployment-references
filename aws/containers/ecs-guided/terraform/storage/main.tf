# Secondary storage stage: Aurora PostgreSQL for the Orchestration Cluster's RDBMS
# secondary storage. It starts as a standalone cluster; see global_cluster_identifier
# and db_instance_class for what to change before turning it into a global database.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_subnet" "private" {
  count = length(var.private_subnet_ids)
  id    = var.private_subnet_ids[count.index]
}

locals {
  # Derived from the subnets rather than the VPC, so it also holds for a VPC you bring.
  availability_zones = sort(distinct(data.aws_subnet.private[*].availability_zone))

  db_admin_password = var.db_admin_password != "" ? var.db_admin_password : random_password.db_admin[0].result

  # Roles that authenticate with an IAM token: the seed users, and the databases with auth = iam.
  iam_usernames      = toset(concat(var.db_seed_iam_usernames, [for k, d in var.databases : d.username if d.auth == "iam"]))
  password_databases = { for k, d in var.databases : k => d if d.auth == "password" }
}

resource "random_password" "db_admin" {
  count = var.db_admin_password == "" ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

module "aurora" {
  source = "../../../../modules/aurora"

  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  engine_version             = "18.6"
  auto_minor_version_upgrade = false
  cluster_name               = "${var.prefix}-camunda-db-cluster"
  default_database_name      = var.db_name

  iam_auth_enabled          = var.db_iam_auth_enabled
  global_cluster_identifier = var.global_cluster_identifier

  availability_zones = local.availability_zones

  username = var.db_admin_username
  password = local.db_admin_password

  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids
  cidr_blocks = concat([var.vpc_cidr], var.additional_cidr_blocks)

  num_instances  = var.db_num_instances
  instance_class = var.db_instance_class
}

################################################################
#                      Admin password secret                   #
################################################################

resource "aws_secretsmanager_secret" "db_admin_password" {
  name                    = "${var.prefix}-db-admin-password"
  description             = "Admin password for the Aurora PostgreSQL cluster (${var.prefix})"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "db_admin_password" {
  secret_id     = aws_secretsmanager_secret.db_admin_password.id
  secret_string = local.db_admin_password
}

resource "aws_iam_policy" "db_admin_password_read" {
  name        = "${var.prefix}-db-admin-secret-read"
  description = "Allow the ECS task execution role to read the database admin password for the seed task"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.db_admin_password.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = var.secrets_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "db_admin_password_read" {
  role       = var.task_execution_role_name
  policy_arn = aws_iam_policy.db_admin_password_read.arn
}

################################################################
#                    IAM database authentication               #
################################################################

# One policy per IAM database user. The Camunda stage attaches the one of its user to
# the task role.
resource "aws_iam_policy" "rds_db_connect" {
  for_each = local.iam_usernames

  name        = "${var.prefix}-rds-db-connect-${each.key}"
  description = "Allow ECS tasks to connect to Aurora PostgreSQL as the IAM database user '${each.key}'"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowRDSDBConnect"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = ["arn:aws:rds-db:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora.aurora_cluster_resource_id}/${each.key}"]
      }
    ]
  })
}

################################################################
#              Passwords of the further databases              #
################################################################

resource "random_password" "database" {
  for_each = local.password_databases

  length           = 32
  special          = true
  override_special = "!#%^()-_=+[]:?"
}

resource "aws_secretsmanager_secret" "database" {
  for_each = local.password_databases

  name                    = "${var.prefix}-${each.key}-db-password"
  description             = "Password of the ${each.value.username} database role (${each.key})"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "database" {
  for_each = local.password_databases

  secret_id     = aws_secretsmanager_secret.database[each.key].id
  secret_string = random_password.database[each.key].result
}

resource "aws_iam_policy" "database_passwords_read" {
  count = length(local.password_databases) > 0 ? 1 : 0

  name        = "${var.prefix}-db-passwords-read"
  description = "Allow the ECS task execution role to read the database passwords of the further databases"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [for k, s in aws_secretsmanager_secret.database : s.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = var.secrets_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "database_passwords_read" {
  count = length(local.password_databases) > 0 ? 1 : 0

  role       = var.task_execution_role_name
  policy_arn = aws_iam_policy.database_passwords_read[0].arn
}
