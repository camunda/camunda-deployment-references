# Task execution and service roles are managed centrally in workspace iam.tf
# Task role remains module-specific due to service-specific permissions (EFS, S3, etc.)

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-orchestration-task-role"

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
    Name = "${var.prefix}-orchestration-task-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_efs_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.efs_sc_access.arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_s3_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_policy" "efs_sc_access" {
  name = "${var.prefix}-efs-sc-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDescribeEFS"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Resource = [
          aws_efs_file_system.efs.arn,
          "${aws_efs_file_system.efs.arn}/*"
        ]
      },
      {
        Sid    = "AllowDescribeEC2"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowEFSClientAccess"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.efs.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      },
      {
        Sid    = "AllowAccessPointOperations"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "elasticfilesystem:TagResource"
        ]
        Resource = aws_efs_file_system.efs.arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessedViaMountTarget" = "true"
          }
        }
      }
    ]
  })
}

# CloudWatch Logs policy for orchestration cluster
resource "aws_iam_policy" "orchestration_cluster_logs_policy" {
  name = "${var.prefix}-orchestration-cluster-logs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.orchestration_cluster_log_group.arn,
          "${aws_cloudwatch_log_group.orchestration_cluster_log_group.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "orchestration_cluster_logs_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.orchestration_cluster_logs_policy.arn
}

# ECS Execute Command permissions
resource "aws_iam_policy" "ecs_exec_policy" {
  name = "${var.prefix}-orchestration-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSSMMessaging"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.prefix}-orchestration-exec-policy"
  }
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
