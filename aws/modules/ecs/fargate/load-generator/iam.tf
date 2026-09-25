resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-load-generator-ecs-task-role"

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
    Name = "${var.prefix}-load-generator-ecs-task-role"
  }
}

# The generator only talks to the Orchestration Cluster over the network, so
# the task role carries nothing by default. Execute-command is the one
# exception, and only when asked for.
resource "aws_iam_policy" "ecs_exec" {
  count = var.task_enable_execute_command ? 1 : 0

  name = "${var.prefix}-load-generator-ecs-exec"

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
