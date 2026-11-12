mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::000000000000:policy/mock"
    }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:mock"
    }
  }
}
mock_provider "random" {}

variables {
  prefix                           = "test"
  vpc_id                           = "vpc-0abc123"
  private_subnet_ids               = ["subnet-a1", "subnet-b2", "subnet-c3"]
  ecs_cluster_id                   = "arn:aws:ecs:eu-west-1:000000000000:cluster/test"
  task_execution_role_arn          = "arn:aws:iam::000000000000:role/exec"
  task_execution_role_name         = "exec"
  secrets_kms_key_arn              = "arn:aws:kms:eu-west-1:000000000000:key/abc"
  camunda_ports_security_group_id  = "sg-ports"
  egress_security_group_id         = "sg-egress"
  efs_security_group_id            = "sg-efs"
  backup_bucket_name               = "backup"
  backup_access_policy_arn         = "arn:aws:iam::000000000000:policy/backup"
  lease_bucket                     = { bucket_name = "lease-zone-a", access_policy_arn = "arn:aws:iam::000000000000:policy/lease" }
  rds_db_connect_policy_arn        = "arn:aws:iam::000000000000:policy/rds"
  alb_listener_http_webapp_arn     = "arn:aws:elasticloadbalancing:eu-west-1:000000000000:listener/app/test/1/2"
  alb_listener_http_management_arn = "arn:aws:elasticloadbalancing:eu-west-1:000000000000:listener/app/test/1/3"
  nlb_grpc_arn                     = "arn:aws:elasticloadbalancing:eu-west-1:000000000000:loadbalancer/net/test/1"
  secondary_storage = {
    type                   = "rdbms"
    host                   = "db.example"
    port                   = 5432
    database_name          = "camunda"
    jdbc_url               = "jdbc:aws-wrapper:postgresql://db.example:5432/camunda?wrapperPlugins=iam"
    jdbc_driver_class_name = "software.amazon.jdbc.Driver"
    iam_auth_enabled       = true
  }
}

run "basic_auth_creates_passwords" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret.admin_user_password) == 1
    error_message = "basic mode must create the admin password secret"
  }
}

run "default_is_one_zone_with_three_brokers" {
  command = plan

  assert {
    condition     = local.cluster_size == 3 && local.replication_factor == 3
    error_message = "default layout is 3 brokers and replication factor 3"
  }
}

run "oidc_skips_basic_secrets" {
  command = plan

  variables {
    oidc = {
      issuer_uri      = "https://idp.example/realms/camunda"
      token_uri       = "https://idp.example/token"
      audience        = "orchestration-api"
      redirect_uri    = "https://camunda.example/sso-callback"
      username_claim  = "preferred_username"
      client_id_claim = "client_id"
      admin_claim     = "admin"
      orchestration   = { client_id = "orchestration", client_secret_arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:o" }
      connectors      = { client_id = "connectors", client_secret_arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:c", token_scope = "" }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.admin_user_password) == 0
    error_message = "OIDC mode must not create basic auth passwords"
  }
}

run "zone_must_be_listed" {
  command = plan

  variables {
    zone = "paris"
  }

  expect_failures = [terraform_data.validate]
}

run "second_region_settings" {
  command = plan

  variables {
    zone = "zone-b"
    zones = [
      { name = "zone-a", number_of_brokers = 3, number_of_replicas = 3, priority = 1000 },
      { name = "zone-b", number_of_brokers = 3, number_of_replicas = 3, priority = 500 },
    ]
    initial_contact_points  = "orchestration-cluster-sc:26502,raft.example:26502"
    cross_region_membership = true
  }

  assert {
    condition     = local.cluster_size == 6 && local.replication_factor == 6
    error_message = "two zones of 3 brokers and 3 replicas make size 6 and replication factor 6"
  }
}

run "supplied_passwords_are_used" {
  command = plan

  variables {
    admin_user_password      = "from-the-first-region"
    connectors_user_password = "from-the-first-region-too"
  }

  assert {
    condition     = output.admin_user_password == "from-the-first-region" && output.connectors_user_password == "from-the-first-region-too"
    error_message = "a second region must reuse the passwords of the first one"
  }
}

run "cluster_registration_for_camunda_hub" {
  command = plan

  assert {
    condition     = output.cluster_registration.version == "8.10.0" && endswith(output.cluster_registration.readiness_url, ":9600/actuator/health/readiness")
    error_message = "Camunda Hub needs the version and the readiness URL of the management port"
  }
}
