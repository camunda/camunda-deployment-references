################################################################
#                ECS Clusters (per region)                     #
################################################################

resource "aws_ecs_cluster" "region_0" {
  name = "${local.prefix_region_0}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster" "region_1" {
  provider = aws.accepter

  name = "${local.prefix_region_1}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
