# One-time seed: creates the database users that authenticate through IAM. The Aurora
# cluster sits in private subnets, so the statements run from a short-lived Fargate task
# inside the VPC instead of from the machine that runs Terraform.

resource "aws_cloudwatch_log_group" "db_seed" {
  count = var.db_seed_enabled ? 1 : 0

  name              = "/ecs/${var.prefix}-db-seed"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "db_seed" {
  count = var.db_seed_enabled ? 1 : 0

  family                   = "${var.prefix}-db-seed"
  execution_role_arn       = var.task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = 256
  memory = 512

  container_definitions = jsonencode([
    {
      name       = "db-seed"
      image      = "public.ecr.aws/docker/library/postgres:17-alpine"
      essential  = true
      entryPoint = ["/bin/sh", "-lc"]
      command = [
        <<-EOT
          set -euo pipefail

          for user in $${IAM_DB_USERS}; do
            echo "Ensuring role exists: $${user}"

            psql "host=$${AURORA_ENDPOINT} port=$${AURORA_PORT} dbname=$${AURORA_DB_NAME} user=$${AURORA_ADMIN_USERNAME} password=$${AURORA_ADMIN_PASSWORD} sslmode=require" \
              -v ON_ERROR_STOP=1 \
              -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$${user}') THEN CREATE ROLE \"$${user}\" WITH LOGIN; END IF; END \$\$;" \
              -c "ALTER ROLE \"$${user}\" WITH LOGIN;" \
              -c "GRANT rds_iam TO \"$${user}\";" \
              -c "GRANT ALL PRIVILEGES ON DATABASE \"$${AURORA_DB_NAME}\" TO \"$${user}\";" \
              -c "GRANT USAGE, CREATE ON SCHEMA public TO \"$${user}\";"
          done

          # Further databases: "<database>:<role>:<auth>" entries.
          for entry in $${DATABASES}; do
            db=$${entry%%:*}
            rest=$${entry#*:}
            role=$${rest%%:*}
            auth=$${rest#*:}
            echo "Provisioning database '$${db}' and role '$${role}' ($${auth} auth)"

            ADMIN="host=$${AURORA_ENDPOINT} port=$${AURORA_PORT} dbname=$${AURORA_DB_NAME} user=$${AURORA_ADMIN_USERNAME} password=$${AURORA_ADMIN_PASSWORD} sslmode=require"

            if [ "$${auth}" = "password" ]; then
              var="DBPW_$(echo "$${role}" | tr a-z A-Z)"
              eval "pw=\$$${var}"
              psql "$${ADMIN}" -v ON_ERROR_STOP=1 \
                -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$${role}') THEN CREATE ROLE \"$${role}\" WITH LOGIN PASSWORD '$${pw}'; END IF; END \$\$;" \
                -c "ALTER ROLE \"$${role}\" WITH LOGIN PASSWORD '$${pw}';"
            else
              psql "$${ADMIN}" -v ON_ERROR_STOP=1 \
                -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$${role}') THEN CREATE ROLE \"$${role}\" WITH LOGIN; END IF; END \$\$;" \
                -c "ALTER ROLE \"$${role}\" WITH LOGIN;" \
                -c "GRANT rds_iam TO \"$${role}\";"
            fi

            # No OWNER: the RDS master role cannot create a database owned by another role.
            psql "$${ADMIN}" -v ON_ERROR_STOP=1 \
              -tc "SELECT 'CREATE DATABASE \"$${db}\"' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$${db}')" \
              | psql "$${ADMIN}" -v ON_ERROR_STOP=1

            psql "host=$${AURORA_ENDPOINT} port=$${AURORA_PORT} dbname=$${db} user=$${AURORA_ADMIN_USERNAME} password=$${AURORA_ADMIN_PASSWORD} sslmode=require" \
              -v ON_ERROR_STOP=1 \
              -c "GRANT ALL PRIVILEGES ON DATABASE \"$${db}\" TO \"$${role}\";" \
              -c "GRANT USAGE, CREATE ON SCHEMA public TO \"$${role}\";"
          done

          echo "DB seeding complete."
        EOT
      ]

      environment = [
        { name = "AURORA_ENDPOINT", value = module.aurora.aurora_endpoint },
        { name = "AURORA_PORT", value = tostring(module.aurora.aurora_port) },
        { name = "AURORA_DB_NAME", value = var.db_name },
        { name = "AURORA_ADMIN_USERNAME", value = var.db_admin_username },
        { name = "IAM_DB_USERS", value = join(" ", var.db_seed_iam_usernames) },
        { name = "DATABASES", value = join(" ", [for k, d in var.databases : "${d.database_name}:${d.username}:${d.auth}"]) },
      ]

      secrets = concat(
        [{ name = "AURORA_ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.db_admin_password.arn }],
        [for k, d in local.password_databases : { name = "DBPW_${upper(d.username)}", valueFrom = aws_secretsmanager_secret.database[k].arn }],
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.db_seed[0].name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "db-seed"
        }
      }
    }
  ])

  depends_on = [
    aws_iam_role_policy_attachment.db_admin_password_read,
    aws_iam_role_policy_attachment.database_passwords_read,
  ]
}

resource "null_resource" "run_db_seed_task" {
  count = var.db_seed_enabled ? 1 : 0

  triggers = {
    aurora_endpoint = module.aurora.aurora_endpoint
    db_name         = var.db_name
    iam_users       = join(",", var.db_seed_iam_usernames)
    databases       = join(",", [for k, d in var.databases : "${d.database_name}:${d.username}:${d.auth}"])
    password_ids    = join(",", [for k, v in aws_secretsmanager_secret_version.database : v.version_id])
    # Re-run when the task definition changes, which is what happens when the SQL is
    # edited. Every statement is idempotent.
    seed_revision = aws_ecs_task_definition.db_seed[0].revision
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail

      NETWORK_CONF='{"awsvpcConfiguration":{"subnets":${jsonencode(var.private_subnet_ids)},"securityGroups":${jsonencode(var.seed_security_group_ids)},"assignPublicIp":"DISABLED"}}'

      echo "Running one-time DB seed task..."
      TASK_ARN=$(aws ecs run-task \
        --region "${data.aws_region.current.region}" \
        --cluster "${var.ecs_cluster_arn}" \
        --launch-type FARGATE \
        --task-definition "${aws_ecs_task_definition.db_seed[0].arn}" \
        --network-configuration "$NETWORK_CONF" \
        --query 'tasks[0].taskArn' \
        --output text)

      aws ecs wait tasks-stopped \
        --region "${data.aws_region.current.region}" \
        --cluster "${var.ecs_cluster_arn}" \
        --tasks "$TASK_ARN"

      EXIT_CODE=$(aws ecs describe-tasks \
        --region "${data.aws_region.current.region}" \
        --cluster "${var.ecs_cluster_arn}" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].containers[0].exitCode' \
        --output text)

      if [ "$EXIT_CODE" != "0" ]; then
        echo "DB seed task failed with exit code $EXIT_CODE. Check the CloudWatch log group /ecs/${var.prefix}-db-seed"
        exit 1
      fi

      echo "DB seed task succeeded."
    EOT
  }

  depends_on = [module.aurora]
}
