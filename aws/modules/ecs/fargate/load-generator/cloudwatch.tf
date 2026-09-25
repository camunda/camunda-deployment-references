resource "aws_cloudwatch_log_group" "load_generator" {
  count = var.log_group_name == "" ? 1 : 0

  name              = "/ecs/${var.prefix}-load-generator"
  retention_in_days = var.log_retention_in_days

  tags = {
    Name = "${var.prefix}-load-generator-log-group"
  }
}
