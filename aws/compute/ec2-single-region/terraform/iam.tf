

resource "aws_iam_policy" "cloudwatch_policy" {
  name        = "${var.prefix}-cloudwatch-policy"
  description = "Policy for CloudWatch to allow monitoring of the EC2 instances"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "CWACloudWatchServerPermissions",
        "Effect" : "Allow",
        "Action" : [
          "cloudwatch:PutMetricData",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "CWASSMServerPermissions",
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameter"
        ],
        "Resource" : "arn:aws:ssm:*:*:parameter/AmazonCloudWatch-*"
      }
    ]
  })

}

resource "aws_iam_role" "cloudwatch" {
  name = "${var.prefix}-cloudwatch"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy_attachment" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = aws_iam_policy.cloudwatch_policy.arn
}

resource "aws_iam_instance_profile" "cloudwatch_instance_profile" {
  name = "${var.prefix}-cloudwatch-instance-profile"
  role = aws_iam_role.cloudwatch.name
}
