resource "aws_cloudwatch_log_group" "core_log_group" {
  name              = "/ecs/${var.prefix}-core"
  retention_in_days = 30

  tags = {
    Name = "${var.prefix}-core-log-group"
  }
}

resource "aws_cloudwatch_log_stream" "core_log_stream" {
  name           = "${var.prefix}-core-log-stream"
  log_group_name = aws_cloudwatch_log_group.core_log_group.name
}
