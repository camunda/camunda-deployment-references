data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "db_seed" {
  count             = var.db_seed_enabled ? 1 : 0
  name              = "/ecs/${var.prefix}-db-seed"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "db_seed" {
  count                    = var.db_seed_enabled ? 1 : 0
  family                   = "${var.prefix}-db-seed"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = 256
  memory = 512

  container_definitions = jsonencode([
    {
      name      = "db-seed"
      image     = "public.ecr.aws/docker/library/postgres:17-alpine"
      essential = true

      entryPoint = ["/bin/sh", "-lc"]
      command = [
        <<-EOT
          set -euo pipefail

          if [ -z "$${IAM_DB_USERS}" ]; then
            echo "No IAM_DB_USERS provided; nothing to do."
            exit 0
          fi

          echo "Seeding database users for IAM auth: $${IAM_DB_USERS}"

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

          echo "DB seeding complete."
        EOT
      ]

      environment = [
        { name = "AURORA_ENDPOINT", value = module.postgresql.aurora_endpoint },
        { name = "AURORA_PORT", value = "5432" },
        { name = "AURORA_DB_NAME", value = var.db_name },
        { name = "AURORA_ADMIN_USERNAME", value = var.db_admin_username },
        { name = "IAM_DB_USERS", value = join(" ", var.db_seed_iam_usernames) }
      ]

      secrets = [
        {
          name      = "AURORA_ADMIN_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_admin_password.arn
        }
      ]

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

  depends_on = [module.postgresql]
}

resource "null_resource" "run_db_seed_task" {
  count = var.db_seed_enabled ? 1 : 0

  triggers = {
    aurora_endpoint = module.postgresql.aurora_endpoint
    db_name         = var.db_name
    iam_users       = join(",", var.db_seed_iam_usernames)
    iam_auth        = tostring(var.db_iam_auth_enabled)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail

      if [ "${var.db_iam_auth_enabled}" != "true" ]; then
        echo "db_seed_enabled=true but db_iam_auth_enabled=false; seeding still runs, but IAM auth won't work until enabled on the cluster."
      fi

      if [ -z "${join(" ", var.db_seed_iam_usernames)}" ]; then
        echo "db_seed_enabled=true but db_seed_iam_usernames is empty; nothing to do."
        exit 0
      fi

      NETWORK_CONF='{"awsvpcConfiguration":{"subnets":${jsonencode(module.vpc.private_subnets)},"securityGroups":${jsonencode([aws_security_group.allow_necessary_camunda_ports_within_vpc.id, aws_security_group.allow_package_80_443.id])},"assignPublicIp":"DISABLED"}}'

      echo "Running one-time DB seed task..."
      TASK_ARN=$(aws ecs run-task \
        --region "${data.aws_region.current.region}" \
        --cluster "${aws_ecs_cluster.ecs.arn}" \
        --launch-type FARGATE \
        --task-definition "${aws_ecs_task_definition.db_seed[0].arn}" \
        --network-configuration "$NETWORK_CONF" \
        --query 'tasks[0].taskArn' \
        --output text)

      echo "Task started: $TASK_ARN"

      aws ecs wait tasks-stopped \
        --region "${data.aws_region.current.region}" \
        --cluster "${aws_ecs_cluster.ecs.arn}" \
        --tasks "$TASK_ARN"

      EXIT_CODE=$(aws ecs describe-tasks \
        --region "${data.aws_region.current.region}" \
        --cluster "${aws_ecs_cluster.ecs.arn}" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].containers[0].exitCode' \
        --output text)

      STOP_REASON=$(aws ecs describe-tasks \
        --region "${data.aws_region.current.region}" \
        --cluster "${aws_ecs_cluster.ecs.arn}" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].stoppedReason' \
        --output text)

      if [ "$EXIT_CODE" != "0" ]; then
        echo "DB seed task failed with exit code $EXIT_CODE. stoppedReason=$STOP_REASON"
        echo "Check logs in CloudWatch log group: /ecs/${var.prefix}-db-seed"
        exit 1
      fi

      echo "DB seed task succeeded."
    EOT
  }

  depends_on = [
    module.postgresql,
    aws_ecs_cluster.ecs,
    aws_ecs_task_definition.db_seed,
  ]
}
