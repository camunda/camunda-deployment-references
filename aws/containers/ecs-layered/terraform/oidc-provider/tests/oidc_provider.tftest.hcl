mock_provider "aws" {
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:mock"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::000000000000:policy/mock"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::000000000000:role/mock"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:000000000000:targetgroup/mock/1"
    }
  }
}
mock_provider "random" {}

variables {
  prefix                          = "mgmt"
  vpc_id                          = "vpc-0abc123"
  private_subnet_ids              = ["subnet-a1", "subnet-b2", "subnet-c3"]
  ecs_cluster_id                  = "arn:aws:ecs:eu-west-1:000000000000:cluster/mgmt"
  task_execution_role_arn         = "arn:aws:iam::000000000000:role/exec"
  task_execution_role_name        = "exec"
  secrets_kms_key_arn             = "arn:aws:kms:eu-west-1:000000000000:key/abc"
  camunda_ports_security_group_id = "sg-ports"
  egress_security_group_id        = "sg-egress"
  service_connect_namespace_arn   = "arn:aws:servicediscovery:eu-west-1:000000000000:namespace/ns-abc"
  log_group_name                  = "/ecs/mgmt-components"
  alb_listener_http_webapp_arn    = "arn:aws:elasticloadbalancing:eu-west-1:000000000000:listener/app/mgmt/1/2"
  public_base_url                 = "https://camunda.example"
  database = {
    database_name       = "oidc_provider"
    username            = "oidc_provider"
    jdbc_url            = "jdbc:postgresql://db.example:5432/oidc_provider"
    password_secret_arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:db"
  }
}

run "one_default_cluster" {
  command = plan

  assert {
    condition     = keys(output.clusters) == ["default"] && output.clusters["default"].orchestration_client_id == "orchestration-default"
    error_message = "one cluster named default unless told otherwise"
  }
}

run "every_cluster_gets_its_own_clients" {
  command = plan

  variables {
    clusters = {
      emea = { base_url = "https://emea.example" }
      apac = { base_url = "https://apac.example" }
    }
  }

  assert {
    condition     = output.clusters["apac"].connectors_client_id == "connectors-apac" && output.clusters["emea"].orchestration_client_id == "orchestration-emea"
    error_message = "each Orchestration Cluster has an orchestration and a connectors client"
  }
}

run "realm_holds_the_clients_of_the_estate" {
  command = apply

  variables {
    enable_camunda_hub = true
    clusters = {
      emea = { base_url = "https://emea.example" }
    }
  }

  assert {
    condition = alltrue([
      contains([for c in jsondecode(aws_secretsmanager_secret_version.realm_import.secret_string).clients : c.clientId], "orchestration-emea"),
      contains([for c in jsondecode(aws_secretsmanager_secret_version.realm_import.secret_string).clients : c.clientId], "camunda-identity"),
      contains([for c in jsondecode(aws_secretsmanager_secret_version.realm_import.secret_string).clients : c.clientId], "web-modeler"),
    ])
    error_message = "the realm must hold a client for each cluster, for Management Identity, and for Camunda Hub when it is enabled"
  }
}

run "hub_client_only_with_hub" {
  command = apply

  assert {
    condition     = !contains([for c in jsondecode(aws_secretsmanager_secret_version.realm_import.secret_string).clients : c.clientId], "web-modeler")
    error_message = "no Camunda Hub client unless Camunda Hub is enabled"
  }
}

run "password_database_required" {
  command = plan

  variables {
    database = {
      database_name       = "oidc_provider"
      username            = "oidc_provider"
      jdbc_url            = "jdbc:aws-wrapper:postgresql://db.example:5432/oidc_provider?wrapperPlugins=iam"
      password_secret_arn = ""
    }
  }

  expect_failures = [var.database]
}

run "cluster_names_are_validated" {
  command = plan

  variables {
    clusters = { "Bad_Name" = {} }
  }

  expect_failures = [var.clusters]
}
