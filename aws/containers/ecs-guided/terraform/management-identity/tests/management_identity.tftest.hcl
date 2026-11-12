mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::000000000000:policy/mock"
    }
  }
}

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
    database_name      = "management_identity"
    username           = "management_identity"
    jdbc_url           = "jdbc:aws-wrapper:postgresql://db.example:5432/management_identity?wrapperPlugins=iam"
    connect_policy_arn = "arn:aws:iam::000000000000:policy/connect"
  }
  oidc = {
    issuer_uri         = "https://camunda.example/auth/realms/camunda-platform"
    issuer_backend_uri = "http://oidc-provider:18080/auth/realms/camunda-platform"
    username_claim     = "preferred_username"
    admin_claim        = "admin"
    identity = {
      client_id         = "camunda-identity"
      client_secret_arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:identity"
      audience          = "camunda-identity-resource-server"
    }
    hub = {
      client_id         = "web-modeler"
      audience_internal = "web-modeler-api"
      audience_public   = "web-modeler-public-api"
    }
  }
}

run "no_hub_roles_by_default" {
  command = plan

  assert {
    condition     = output.authorization == null && !output.hub_authorization_enabled
    error_message = "the roles of Camunda Hub are declared only on demand"
  }
}

run "hub_authorization_declares_roles_and_grants_them_to_the_administrator" {
  command = plan

  variables {
    enable_hub_authorization = true
  }

  assert {
    condition = alltrue([
      contains(output.authorization.identity["mapping-rules"][0]["applied-role-names"], "Web Modeler"),
      contains(output.authorization.identity["mapping-rules"][0]["applied-role-names"], "Web Modeler Admin"),
      contains(output.authorization.identity["mapping-rules"][0]["applied-role-names"], "ManagementIdentity"),
      output.authorization.identity["mapping-rules"][0]["claim-value"] == "admin",
    ])
    error_message = "the administrator must receive every declared role"
  }
}

run "iam_database_required" {
  command = plan

  variables {
    database = {
      database_name      = "management_identity"
      username           = "management_identity"
      jdbc_url           = "jdbc:postgresql://db.example:5432/management_identity"
      connect_policy_arn = ""
    }
  }

  expect_failures = [var.database]
}
