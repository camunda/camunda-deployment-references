# Golden-plan fixture (Terraform override file, copied into the module root by
# the `regenerate-golden-file` recipe and removed afterwards).
#
# The app/ state cannot be planned standalone because it reads the sibling
# infra/ state via data.terraform_remote_state.infra over an S3 backend that
# does not exist during golden generation. Here we:
#   1. disable that read (count = 0) so no backend is contacted, and
#   2. replace local.infra with a static, deterministic snapshot of the infra
#      outputs the app consumes.
# This makes the app plan fully offline and reproducible while still exercising
# the real Camunda ECS resources (task definitions, services, env vars) — which
# is the drift we want the golden file to catch.
#
# Values are placeholders; ARNs use account 000000000000 and are redacted from
# the committed golden JSON by the recipe. secondary_storage_type = "rdbms"
# matches the module default (Aurora Global; OpenSearch outputs are null).

data "terraform_remote_state" "infra" {
  count = 0
}

locals {
  infra = {
    # Region & naming
    region_0               = "eu-west-2"
    region_1               = "eu-west-3"
    cluster_name           = "camunda"
    secondary_storage_type = "rdbms"

    # VPC (re-exported from vpc state)
    vpc_region_0_id              = "vpc-00000000000000000"
    vpc_region_1_id              = "vpc-11111111111111111"
    vpc_region_0_private_subnets = ["subnet-000000000000000a0", "subnet-000000000000000b0", "subnet-000000000000000c0"]
    vpc_region_1_private_subnets = ["subnet-000000000000000a1", "subnet-000000000000000b1", "subnet-000000000000000c1"]

    # ECS clusters
    ecs_cluster_region_0_id = "arn:aws:ecs:eu-west-2:000000000000:cluster/camunda-r0"
    ecs_cluster_region_1_id = "arn:aws:ecs:eu-west-3:000000000000:cluster/camunda-r1"

    # Load balancers
    region_0_alb_endpoint                     = "camunda-r0-alb.eu-west-2.elb.amazonaws.com"
    region_1_alb_endpoint                     = "camunda-r1-alb.eu-west-3.elb.amazonaws.com"
    alb_listener_http_webapp_region_0_arn     = "arn:aws:elasticloadbalancing:eu-west-2:000000000000:listener/app/camunda-r0/0000000000000000/0000000000000000"
    alb_listener_http_webapp_region_1_arn     = "arn:aws:elasticloadbalancing:eu-west-3:000000000000:listener/app/camunda-r1/1111111111111111/1111111111111111"
    alb_listener_http_management_region_0_arn = "arn:aws:elasticloadbalancing:eu-west-2:000000000000:listener/app/camunda-r0/0000000000000000/0000000000000001"
    alb_listener_http_management_region_1_arn = "arn:aws:elasticloadbalancing:eu-west-3:000000000000:listener/app/camunda-r1/1111111111111111/1111111111111112"
    nlb_grpc_region_0_arn                     = "arn:aws:elasticloadbalancing:eu-west-2:000000000000:loadbalancer/net/camunda-r0-grpc/0000000000000000"
    nlb_grpc_region_1_arn                     = "arn:aws:elasticloadbalancing:eu-west-3:000000000000:loadbalancer/net/camunda-r1-grpc/1111111111111111"
    nlb_raft_region_0_arn                     = "arn:aws:elasticloadbalancing:eu-west-2:000000000000:loadbalancer/net/camunda-r0-raft/0000000000000000"
    nlb_raft_region_1_arn                     = "arn:aws:elasticloadbalancing:eu-west-3:000000000000:loadbalancer/net/camunda-r1-raft/1111111111111111"
    region_0_nlb_raft_endpoint                = "camunda-r0-raft.elb.eu-west-2.amazonaws.com"
    region_1_nlb_raft_endpoint                = "camunda-r1-raft.elb.eu-west-3.amazonaws.com"
    region_0_nlb_grpc_endpoint                = "camunda-r0-grpc.elb.eu-west-2.amazonaws.com"
    region_1_nlb_grpc_endpoint                = "camunda-r1-grpc.elb.eu-west-3.amazonaws.com"

    # Security groups
    sg_camunda_ports_region_0_id  = "sg-0000000000000000a"
    sg_camunda_ports_region_1_id  = "sg-0000000000000001a"
    sg_package_80_443_region_0_id = "sg-0000000000000000b"
    sg_package_80_443_region_1_id = "sg-0000000000000001b"
    sg_efs_region_0_id            = "sg-0000000000000000c"
    sg_efs_region_1_id            = "sg-0000000000000001c"

    # IAM
    ecs_task_execution_role_region_0_arn = "arn:aws:iam::000000000000:role/camunda-r0-task-execution"
    ecs_task_execution_role_region_1_arn = "arn:aws:iam::000000000000:role/camunda-r1-task-execution"
    rds_db_connect_policy_region_0_arn   = "arn:aws:iam::000000000000:policy/camunda-r0-rds-connect"
    rds_db_connect_policy_region_1_arn   = "arn:aws:iam::000000000000:policy/camunda-r1-rds-connect"
    s3_backup_access_policy_region_0_arn = "arn:aws:iam::000000000000:policy/camunda-r0-s3-backup"

    # Secrets
    admin_user_password                     = "golden-placeholder-admin-password"
    admin_user_password_secret_region_0_arn = "arn:aws:secretsmanager:eu-west-2:000000000000:secret:camunda-r0-admin-000000"
    admin_user_password_secret_region_1_arn = "arn:aws:secretsmanager:eu-west-3:000000000000:secret:camunda-r1-admin-111111"
    connectors_password_secret_region_0_arn = "arn:aws:secretsmanager:eu-west-2:000000000000:secret:camunda-r0-connectors-000000"
    connectors_password_secret_region_1_arn = "arn:aws:secretsmanager:eu-west-3:000000000000:secret:camunda-r1-connectors-111111"
    registry_credentials_region_0_arn       = ""
    registry_credentials_region_1_arn       = ""

    # Aurora (rdbms mode)
    aurora_global_writer_endpoint       = "camunda-global.cluster-r00000000000.eu-west-2.rds.amazonaws.com"
    aurora_primary_cluster_endpoint     = "camunda-primary.cluster-r00000000000.eu-west-2.rds.amazonaws.com"
    aurora_primary_cluster_identifier   = "camunda-primary"
    aurora_secondary_cluster_identifier = "camunda-secondary"
    aurora_secondary_cluster_endpoint   = "camunda-secondary.cluster-r11111111111.eu-west-3.rds.amazonaws.com"

    # OpenSearch (null in rdbms mode)
    opensearch_region_0_endpoint = null
    opensearch_region_1_endpoint = null

    # S3 backup / database
    backup_bucket_region_0_name = "camunda-backup-eu-west-2"
    s3_force_destroy            = true
    db_name                     = "camunda"
    db_admin_username           = "camunda"
  }
}
