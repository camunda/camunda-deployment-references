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


resource "aws_cloudwatch_log_group" "prometheus_log_group" {
  name              = "/ecs/${var.prefix}-prometheus"
  retention_in_days = 7
  tags = { Name = "${var.prefix}-prometheus-log-group" }
}

resource "aws_cloudwatch_log_stream" "prometheus_log_stream" {
  name           = "${var.prefix}-prometheus-log-stream"
  log_group_name = aws_cloudwatch_log_group.prometheus_log_group.name
}

resource "aws_cloudwatch_log_group" "grafana_log_group" {
  name              = "/ecs/${var.prefix}-grafana"
  retention_in_days = 7
  tags = { Name = "${var.prefix}-grafana-log-group" }
}

resource "aws_cloudwatch_log_stream" "grafana_log_stream" {
  name           = "${var.prefix}-grafana-log-stream"
  log_group_name = aws_cloudwatch_log_group.grafana_log_group.name
}


resource "aws_cloudwatch_log_group" "starter_log_group" {
  name              = "/ecs/${var.prefix}-starter"
  retention_in_days = 7
  tags = { Name = "${var.prefix}-starter-log-group" }
}

resource "aws_cloudwatch_log_group" "worker_log_group" {
  name              = "/ecs/${var.prefix}-worker"
  retention_in_days = 7
  tags = { Name = "${var.prefix}-worker-log-group" }
}
