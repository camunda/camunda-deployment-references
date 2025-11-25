resource "aws_cloudwatch_log_group" "orchestration_cluster_log_group" {
  name              = "/ecs/${var.prefix}-camunda"
  retention_in_days = var.cloudwatch_retention_days

  tags = {
    Name = "${var.prefix}-oc-log-group"
  }
}

resource "aws_cloudwatch_log_stream" "orchestration_cluster_log_stream" {
  name           = "${var.prefix}-orchestration-cluster-log-stream"
  log_group_name = aws_cloudwatch_log_group.orchestration_cluster_log_group.name
}
