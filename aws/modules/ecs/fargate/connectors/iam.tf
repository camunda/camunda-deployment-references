resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.prefix}-con-ecs-task-execution-role"

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
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_service" {
  name = "${var.prefix}-con-ecs-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_service" {
  name   = "${var.prefix}-con-ecs-service-role-policy"
  role   = aws_iam_role.ecs_service.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*",
        "ec2:*",
        "ecs:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

# Create a separate task role for EFS access
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-con-ecs-task-role"

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
}

# Add ECS Execute Command permissions to task role
resource "aws_iam_policy" "ecs_exec_policy" {
  name = "${var.prefix}-con-ecs-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_exec_policy.arn
}

# Attach extra task role policies
resource "aws_iam_role_policy_attachment" "task_role_policy_attachment" {
  count = length(var.extra_task_role_attachments)

  role       = aws_iam_role.ecs_task_role.name
  policy_arn = var.extra_task_role_attachments[count.index]
}

resource "aws_iam_role_policy_attachment" "service_role_policy_attachment" {
  count = length(var.extra_service_role_attachments)

  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = var.extra_service_role_attachments[count.index]
}
