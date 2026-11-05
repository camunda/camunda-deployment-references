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
}
mock_provider "random" {}

variables {
  prefix                                        = "mgmt"
  vpc_id                                        = "vpc-0abc123"
  private_subnet_ids                            = ["subnet-a1", "subnet-b2", "subnet-c3"]
  ecs_cluster_id                                = "arn:aws:ecs:eu-west-1:000000000000:cluster/mgmt"
  task_execution_role_arn                       = "arn:aws:iam::000000000000:role/exec"
  task_execution_role_name                      = "exec"
  secrets_kms_key_arn                           = "arn:aws:kms:eu-west-1:000000000000:key/abc"
  camunda_ports_security_group_id               = "sg-ports"
  egress_security_group_id                      = "sg-egress"
  service_connect_namespace_arn                 = "arn:aws:servicediscovery:eu-west-1:000000000000:namespace/ns-abc"
  log_group_name                                = "/ecs/mgmt-components"
  alb_listener_http_webapp_arn                  = "arn:aws:elasticloadbalancing:eu-west-1:000000000000:listener/app/mgmt/1/2"
  public_base_url                               = "https://camunda.example"
  management_identity_url                       = "http://identity:8084/identity"
  management_identity_hub_authorization_enabled = true
  database = {
    database_name      = "camunda_hub"
    username           = "camunda_hub"
    jdbc_url           = "jdbc:aws-wrapper:postgresql://db.example:5432/camunda_hub?wrapperPlugins=iam"
    connect_policy_arn = "arn:aws:iam::000000000000:policy/connect"
  }
  oidc = {
    issuer_uri         = "https://camunda.example/auth/realms/camunda-platform"
    issuer_backend_uri = "http://oidc-provider:18080/auth/realms/camunda-platform"
    hub = {
      client_id         = "web-modeler"
      audience_internal = "web-modeler-api"
      audience_public   = "web-modeler-public-api"
    }
  }
  clusters = {
    emea = {
      version       = "8.10.0"
      rest_url      = "http://orchestration-cluster.emea-oc.service.local:8080"
      grpc_url      = "grpc://orchestration-cluster.emea-oc.service.local:26500"
      readiness_url = "http://orchestration-cluster.emea-oc.service.local:9600/actuator/health/readiness"
    }
  }
}

run "one_hub_several_clusters" {
  command = plan

  variables {
    clusters = {
      emea = {
        version       = "8.10.0"
        rest_url      = "http://orchestration-cluster.emea-oc.service.local:8080"
        grpc_url      = "grpc://orchestration-cluster.emea-oc.service.local:26500"
        readiness_url = "http://orchestration-cluster.emea-oc.service.local:9600/actuator/health/readiness"
      }
      apac = {
        name          = "Asia Pacific"
        version       = "8.10.0"
        rest_url      = "http://orchestration-cluster.apac-oc.service.local:8080"
        grpc_url      = "grpc://orchestration-cluster.apac-oc.service.local:26500"
        readiness_url = "http://orchestration-cluster.apac-oc.service.local:9600/actuator/health/readiness"
      }
    }
  }

  assert {
    condition     = join(",", output.clusters) == "apac,emea" && length(output.clusters_config) == 2
    error_message = "a single Camunda Hub must be configured with every listed cluster"
  }

  assert {
    condition     = one([for c in output.clusters_config : c.name if c.id == "apac"]) == "Asia Pacific" && one([for c in output.clusters_config : c.name if c.id == "emea"]) == "emea"
    error_message = "the name defaults to the ID"
  }
}

run "management_identity_must_declare_the_hub_roles" {
  command = plan

  variables {
    management_identity_hub_authorization_enabled = false
  }

  expect_failures = [var.management_identity_hub_authorization_enabled]
}

run "at_least_one_cluster" {
  command = plan

  variables {
    clusters = {}
  }

  expect_failures = [var.clusters]
}

run "iam_database_required" {
  command = plan

  variables {
    database = {
      database_name      = "camunda_hub"
      username           = "camunda_hub"
      jdbc_url           = "jdbc:postgresql://db.example:5432/camunda_hub"
      connect_policy_arn = ""
    }
  }

  expect_failures = [var.database]
}
