resource "aws_cloudwatch_log_group" "log_group" {
  count = length(var.log_types) > 0 ? 1 : 0
  name  = "${var.domain_name}-os-logs"
}

data "aws_iam_policy_document" "log_policy_document" {
  count = length(var.log_types) > 0 ? 1 : 0
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["es.amazonaws.com"]
    }

    actions = [
      "logs:PutLogEvents",
      "logs:PutLogEventsBatch",
      "logs:CreateLogStream",
    ]

    resources = ["arn:aws:logs:*"]
  }
}

resource "aws_cloudwatch_log_resource_policy" "log_policy" {
  count           = length(var.log_types) > 0 ? 1 : 0
  policy_name     = "${var.domain_name}-os-log-policy"
  policy_document = join("", data.aws_iam_policy_document.log_policy_document[*].json)
}
