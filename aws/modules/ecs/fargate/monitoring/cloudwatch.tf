resource "aws_cloudwatch_log_group" "monitoring" {
  count = var.log_group_name == "" ? 1 : 0

  name              = "/ecs/${var.prefix}-monitoring"
  retention_in_days = var.log_retention_in_days

  tags = {
    Name = "${var.prefix}-monitoring-log-group"
  }
}
