mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::000000000000:policy/mock"
    }
  }
}

variables {
  prefix = "test"
}

run "basic_mode_outputs_null" {
  command = plan

  assert {
    condition     = output.oidc == null && output.authentication_mode == "basic"
    error_message = "basic mode must not produce an oidc object"
  }
}

run "oidc_requires_external_oidc" {
  command = plan

  variables {
    authentication_mode = "oidc"
  }

  expect_failures = [terraform_data.validate]
}

run "external_oidc_builds_contract" {
  command = plan

  variables {
    authentication_mode      = "oidc"
    public_base_url          = "https://camunda.example"
    task_execution_role_name = "exec"
    secrets_kms_key_arn      = "arn:aws:kms:eu-west-1:000000000000:key/abc"
    external_oidc = {
      issuer_uri                      = "https://idp.example"
      token_uri                       = "https://idp.example/token"
      orchestration_audience          = "orchestration-api"
      orchestration_client_id         = "orchestration"
      orchestration_client_secret_arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:o"
      connectors_client_id            = "connectors"
      connectors_client_secret_arn    = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:c"
    }
  }

  assert {
    condition     = output.oidc.redirect_uri == "https://camunda.example/sso-callback" && output.oidc.username_claim == "preferred_username"
    error_message = "the contract must carry the redirect URI and the default claims"
  }
}

run "empty_field_rejected" {
  command = plan

  variables {
    authentication_mode      = "oidc"
    public_base_url          = "https://camunda.example"
    task_execution_role_name = "exec"
    secrets_kms_key_arn      = "arn:aws:kms:eu-west-1:000000000000:key/abc"
    external_oidc = {
      issuer_uri                      = ""
      token_uri                       = "https://idp.example/token"
      orchestration_audience          = "orchestration-api"
      orchestration_client_id         = "orchestration"
      orchestration_client_secret_arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:o"
      connectors_client_id            = "connectors"
      connectors_client_secret_arn    = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:c"
    }
  }

  expect_failures = [terraform_data.validate]
}

run "client_secrets_of_another_key_are_decryptable" {
  command = plan

  variables {
    authentication_mode      = "oidc"
    public_base_url          = "https://camunda.example"
    task_execution_role_name = "exec"
    secrets_kms_key_arn      = "arn:aws:kms:eu-west-1:000000000000:key/local"
    external_oidc = {
      issuer_uri                      = "https://idp.example"
      token_uri                       = "https://idp.example/token"
      orchestration_audience          = "orchestration-api"
      orchestration_client_id         = "orchestration"
      orchestration_client_secret_arn = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:o"
      connectors_client_id            = "connectors"
      connectors_client_secret_arn    = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:c"
      client_secrets_kms_key_arn      = "arn:aws:kms:eu-west-1:000000000000:key/management"
    }
  }

  assert {
    condition     = length(jsondecode(aws_iam_policy.client_secrets_read[0].policy).Statement[1].Resource) == 2
    error_message = "the execution role must be allowed to decrypt with the key that encrypted the client secrets"
  }
}
