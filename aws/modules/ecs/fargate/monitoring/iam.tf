resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-monitoring-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.prefix}-monitoring-ecs-task-role"
  }
}

# The discovery sidecar reads Cloud Map to find the orchestration clusters.
# These three List* actions have no resource-level permissions in IAM, so the
# resource has to stay "*"; the policy is kept read-only to compensate.
resource "aws_iam_policy" "cloudmap_discovery" {
  name = "${var.prefix}-monitoring-cloudmap-discovery"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudMapDiscovery"
        Effect = "Allow"
        Action = [
          "servicediscovery:ListNamespaces",
          "servicediscovery:ListServices",
          "servicediscovery:ListInstances",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudmap_discovery" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.cloudmap_discovery.arn
}

# Only attached when the operator asks for `aws ecs execute-command`, so a
# default deployment carries no SSM channel permissions at all.
resource "aws_iam_policy" "ecs_exec" {
  count = var.task_enable_execute_command ? 1 : 0

  name = "${var.prefix}-monitoring-ecs-exec"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec" {
  count = var.task_enable_execute_command ? 1 : 0

  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_exec[0].arn
}
