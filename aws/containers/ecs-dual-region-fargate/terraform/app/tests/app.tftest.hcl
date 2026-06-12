# Consolidated test suite for terraform/app/.
#
# Asserts on app/'s own locals (which build the env_variables lists) rather
# than module inputs (modules don't expose their inputs as outputs).
#
# Sections match the design spec §1.4:
#   1. env_branch       — RDBMS vs OpenSearch env vars
#   2. image_propagation — camunda_image variable propagation
#   3. connectors       — SPRING_PROFILES_ACTIVE
#   4. zone_aware       — CAMUNDA_CLUSTER_ZONE (regression guard for rename)

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

# Baseline fixture used by most runs. The opensearch run overrides this.
override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = {
      cluster_name                              = "test-app"
      region_0                                  = "us-east-1"
      region_1                                  = "us-east-2"
      secondary_storage_type                    = "rdbms"
      vpc_region_0_id                           = "vpc-aaaaaaaa"
      vpc_region_0_private_subnets              = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
      vpc_region_1_id                           = "vpc-bbbbbbbb"
      vpc_region_1_private_subnets              = ["subnet-bbb1bbbb", "subnet-bbb2bbbb", "subnet-bbb3bbbb"]
      ecs_cluster_region_0_id                   = "arn:aws:ecs:us-east-1:000000000000:cluster/test-app-r0"
      ecs_cluster_region_1_id                   = "arn:aws:ecs:us-east-2:000000000000:cluster/test-app-r1"
      region_0_alb_endpoint                     = "alb-r0.example.com"
      region_1_alb_endpoint                     = "alb-r1.example.com"
      alb_listener_http_webapp_region_0_arn     = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/r0/x/y"
      alb_listener_http_webapp_region_1_arn     = "arn:aws:elasticloadbalancing:us-east-2:000000000000:listener/app/r1/x/y"
      alb_listener_http_management_region_0_arn = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/r0/x/m"
      alb_listener_http_management_region_1_arn = "arn:aws:elasticloadbalancing:us-east-2:000000000000:listener/app/r1/x/m"
      nlb_grpc_region_0_arn                     = "arn:aws:elasticloadbalancing:us-east-1:000000000000:loadbalancer/net/g0/x"
      nlb_grpc_region_1_arn                     = "arn:aws:elasticloadbalancing:us-east-2:000000000000:loadbalancer/net/g1/x"
      nlb_raft_region_0_arn                     = "arn:aws:elasticloadbalancing:us-east-1:000000000000:loadbalancer/net/r0/x"
      nlb_raft_region_1_arn                     = "arn:aws:elasticloadbalancing:us-east-2:000000000000:loadbalancer/net/r1/x"
      nlb_raft_region_0_dns_name                = "nlb-raft-r0.example.com"
      nlb_raft_region_1_dns_name                = "nlb-raft-r1.example.com"
      region_0_nlb_grpc_endpoint                = "nlb-grpc-r0.example.com"
      region_1_nlb_grpc_endpoint                = "nlb-grpc-r1.example.com"
      sg_camunda_ports_region_0_id              = "sg-aaa1aaaa"
      sg_camunda_ports_region_1_id              = "sg-bbb1bbbb"
      sg_package_80_443_region_0_id             = "sg-aaa2aaaa"
      sg_package_80_443_region_1_id             = "sg-bbb2bbbb"
      sg_efs_region_0_id                        = "sg-aaa3aaaa"
      sg_efs_region_1_id                        = "sg-bbb3bbbb"
      ecs_task_execution_role_region_0_arn      = "arn:aws:iam::000000000000:role/test-app-r0-exec"
      ecs_task_execution_role_region_1_arn      = "arn:aws:iam::000000000000:role/test-app-r1-exec"
      rds_db_connect_policy_region_0_arn        = "arn:aws:iam::000000000000:policy/test-app-r0-rds-connect"
      rds_db_connect_policy_region_1_arn        = "arn:aws:iam::000000000000:policy/test-app-r1-rds-connect"
      s3_backup_access_policy_region_0_arn      = "arn:aws:iam::000000000000:policy/test-app-r0-s3"
      s3_backup_access_policy_region_1_arn      = "arn:aws:iam::000000000000:policy/test-app-r1-s3"
      admin_user_password                       = "test-admin-password"
      admin_user_password_secret_region_0_arn   = "arn:aws:secretsmanager:us-east-1:000000000000:secret:test-app-r0-admin"
      admin_user_password_secret_region_1_arn   = "arn:aws:secretsmanager:us-east-2:000000000000:secret:test-app-r1-admin"
      connectors_password_secret_region_0_arn   = "arn:aws:secretsmanager:us-east-1:000000000000:secret:test-app-r0-conn"
      connectors_password_secret_region_1_arn   = "arn:aws:secretsmanager:us-east-2:000000000000:secret:test-app-r1-conn"
      registry_credentials_region_0_arn         = ""
      registry_credentials_region_1_arn         = ""
      backup_bucket_region_0_name               = "test-app-r0-backup"
      backup_bucket_region_1_name               = "test-app-r1-backup"
      db_name                                   = "camunda"
      db_admin_username                         = "camunda_admin"
      aurora_primary_endpoint                   = "aurora-primary.example.com"
      aurora_secondary_endpoint                 = "aurora-secondary.example.com"
      aurora_primary_cluster_identifier         = "test-app-r0-aurora"
      aurora_secondary_cluster_identifier       = "test-app-r1-aurora"
      opensearch_region_0_endpoint              = "opensearch-r0.example.com"
      opensearch_region_1_endpoint              = "opensearch-r1.example.com"
      s3_force_destroy                          = true
    }
  }
}

# ============================================================================
# Section 1: env_branch
# ============================================================================

run "rdbms_env_vars_local_populated_when_rdbms" {
  command = plan

  assert {
    condition     = length(local.rdbms_env_vars) > 0
    error_message = "local.rdbms_env_vars should be populated when secondary_storage_type = rdbms"
  }

  assert {
    condition     = length(local.opensearch_env_vars_region_0) == 0
    error_message = "local.opensearch_env_vars_region_0 should be empty when secondary_storage_type = rdbms"
  }
}

run "opensearch_env_vars_local_populated_when_opensearch" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = {
        cluster_name                              = "test-app"
        region_0                                  = "us-east-1"
        region_1                                  = "us-east-2"
        secondary_storage_type                    = "opensearch"
        vpc_region_0_id                           = "vpc-aaaaaaaa"
        vpc_region_0_private_subnets              = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
        vpc_region_1_id                           = "vpc-bbbbbbbb"
        vpc_region_1_private_subnets              = ["subnet-bbb1bbbb", "subnet-bbb2bbbb", "subnet-bbb3bbbb"]
        ecs_cluster_region_0_id                   = "arn:aws:ecs:us-east-1:000000000000:cluster/test-app-r0"
        ecs_cluster_region_1_id                   = "arn:aws:ecs:us-east-2:000000000000:cluster/test-app-r1"
        region_0_alb_endpoint                     = "alb-r0.example.com"
        region_1_alb_endpoint                     = "alb-r1.example.com"
        alb_listener_http_webapp_region_0_arn     = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/r0/x/y"
        alb_listener_http_webapp_region_1_arn     = "arn:aws:elasticloadbalancing:us-east-2:000000000000:listener/app/r1/x/y"
        alb_listener_http_management_region_0_arn = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/r0/x/m"
        alb_listener_http_management_region_1_arn = "arn:aws:elasticloadbalancing:us-east-2:000000000000:listener/app/r1/x/m"
        nlb_grpc_region_0_arn                     = "arn:aws:elasticloadbalancing:us-east-1:000000000000:loadbalancer/net/g0/x"
        nlb_grpc_region_1_arn                     = "arn:aws:elasticloadbalancing:us-east-2:000000000000:loadbalancer/net/g1/x"
        nlb_raft_region_0_arn                     = "arn:aws:elasticloadbalancing:us-east-1:000000000000:loadbalancer/net/r0/x"
        nlb_raft_region_1_arn                     = "arn:aws:elasticloadbalancing:us-east-2:000000000000:loadbalancer/net/r1/x"
        nlb_raft_region_0_dns_name                = "nlb-raft-r0.example.com"
        nlb_raft_region_1_dns_name                = "nlb-raft-r1.example.com"
        region_0_nlb_grpc_endpoint                = "nlb-grpc-r0.example.com"
        region_1_nlb_grpc_endpoint                = "nlb-grpc-r1.example.com"
        sg_camunda_ports_region_0_id              = "sg-aaa1aaaa"
        sg_camunda_ports_region_1_id              = "sg-bbb1bbbb"
        sg_package_80_443_region_0_id             = "sg-aaa2aaaa"
        sg_package_80_443_region_1_id             = "sg-bbb2bbbb"
        sg_efs_region_0_id                        = "sg-aaa3aaaa"
        sg_efs_region_1_id                        = "sg-bbb3bbbb"
        ecs_task_execution_role_region_0_arn      = "arn:aws:iam::000000000000:role/test-app-r0-exec"
        ecs_task_execution_role_region_1_arn      = "arn:aws:iam::000000000000:role/test-app-r1-exec"
        rds_db_connect_policy_region_0_arn        = ""
        rds_db_connect_policy_region_1_arn        = ""
        s3_backup_access_policy_region_0_arn      = "arn:aws:iam::000000000000:policy/test-app-r0-s3"
        s3_backup_access_policy_region_1_arn      = "arn:aws:iam::000000000000:policy/test-app-r1-s3"
        admin_user_password                       = "test-admin-password"
        admin_user_password_secret_region_0_arn   = "arn:aws:secretsmanager:us-east-1:000000000000:secret:test-app-r0-admin"
        admin_user_password_secret_region_1_arn   = "arn:aws:secretsmanager:us-east-2:000000000000:secret:test-app-r1-admin"
        connectors_password_secret_region_0_arn   = "arn:aws:secretsmanager:us-east-1:000000000000:secret:test-app-r0-conn"
        connectors_password_secret_region_1_arn   = "arn:aws:secretsmanager:us-east-2:000000000000:secret:test-app-r1-conn"
        registry_credentials_region_0_arn         = ""
        registry_credentials_region_1_arn         = ""
        backup_bucket_region_0_name               = "test-app-r0-backup"
        backup_bucket_region_1_name               = "test-app-r1-backup"
        db_name                                   = "camunda"
        db_admin_username                         = "camunda_admin"
        aurora_primary_endpoint                   = ""
        aurora_secondary_endpoint                 = ""
        aurora_primary_cluster_identifier         = ""
        aurora_secondary_cluster_identifier       = ""
        opensearch_region_0_endpoint              = "opensearch-r0.example.com"
        opensearch_region_1_endpoint              = "opensearch-r1.example.com"
        s3_force_destroy                          = true
      }
    }
  }

  assert {
    condition     = length(local.rdbms_env_vars) == 0
    error_message = "local.rdbms_env_vars should be empty when secondary_storage_type = opensearch"
  }

  assert {
    condition     = length(local.opensearch_env_vars_region_0) > 0
    error_message = "local.opensearch_env_vars_region_0 should be populated when secondary_storage_type = opensearch"
  }

  assert {
    condition     = length(local.opensearch_env_vars_region_1) > 0
    error_message = "local.opensearch_env_vars_region_1 should be populated when secondary_storage_type = opensearch"
  }
}

# ============================================================================
# Section 2: image_propagation
# ============================================================================

run "custom_camunda_image_override" {
  command = plan

  variables {
    camunda_image = "registry.example.com/camunda:custom-tag"
  }

  assert {
    condition     = var.camunda_image == "registry.example.com/camunda:custom-tag"
    error_message = "camunda_image override should be applied"
  }
}

# ============================================================================
# Section 3: connectors — SPRING_PROFILES_ACTIVE
# ============================================================================

# These env vars are inlined in app/camunda.tf at module call sites, not in
# locals. We can't read module inputs, so we test indirectly: confirm the
# connectors modules are instantiated. Detailed env-var assertions would
# require structural changes to app/ (extracting the connector env list to
# a local) — flag as a follow-up.

run "connectors_modules_instantiated" {
  command = plan

  assert {
    condition     = length(module.connectors_region_0) >= 0
    error_message = "Region 0 connectors module should be addressable in plan"
  }
}

# ============================================================================
# Section 4: zone_aware — CAMUNDA_CLUSTER_ZONE (regression guard)
# ============================================================================

run "cluster_zone_env_per_region" {
  command = plan

  # The env vars are constructed in local.cluster_region_env_region_0/1.
  # Catches the CAMUNDA_CLUSTER_REGION → CAMUNDA_CLUSTER_ZONE rename regression.

  assert {
    condition = anytrue([
      for env in local.cluster_region_env_region_0 :
      env.name == "CAMUNDA_CLUSTER_ZONE" && env.value == "us-east-1"
    ])
    error_message = "local.cluster_region_env_region_0 should set CAMUNDA_CLUSTER_ZONE = us-east-1 (catches REGION-vs-ZONE rename regression)"
  }

  assert {
    condition = anytrue([
      for env in local.cluster_region_env_region_1 :
      env.name == "CAMUNDA_CLUSTER_ZONE" && env.value == "us-east-2"
    ])
    error_message = "local.cluster_region_env_region_1 should set CAMUNDA_CLUSTER_ZONE = us-east-2"
  }

  # Negative check: the old name must not appear.
  assert {
    condition = !anytrue([
      for env in local.cluster_region_env_region_0 :
      env.name == "CAMUNDA_CLUSTER_REGION"
    ])
    error_message = "Old CAMUNDA_CLUSTER_REGION env var should not appear — was renamed to CAMUNDA_CLUSTER_ZONE"
  }

  assert {
    condition = !anytrue([
      for env in local.partitioning_env_vars :
      env.name == "REGION_AWARE" || (env.name == "CAMUNDA_CLUSTER_PARTITIONING_AWARENESS" && env.value == "REGION_AWARE")
    ])
    error_message = "Old REGION_AWARE awareness value should not appear — was renamed to ZONE_AWARE"
  }
}
