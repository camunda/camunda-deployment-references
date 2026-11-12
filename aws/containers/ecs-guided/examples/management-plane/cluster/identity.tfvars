# The identity stage of an Orchestration Cluster that signs in against the management plane's
# OIDC provider. Copy the object from the OIDC provider stage:
#
#   terraform -chdir=terraform/oidc-provider output -json clusters | jq '.emea'
prefix              = "camunda-emea"
authentication_mode = "oidc"

admin_claim_value = "admin"

external_oidc = {
  issuer_uri                      = "https://camunda.example.com/auth/realms/camunda-platform"
  token_uri                       = "https://camunda.example.com/auth/realms/camunda-platform/protocol/openid-connect/token"
  orchestration_audience          = "orchestration-api"
  orchestration_client_id         = "orchestration-emea"
  orchestration_client_secret_arn = "arn:aws:secretsmanager:eu-west-1:111111111111:secret:camunda-mgmt-oidc-orchestration-emea-client-secret-AbCdEf"
  connectors_client_id            = "connectors-emea"
  connectors_client_secret_arn    = "arn:aws:secretsmanager:eu-west-1:111111111111:secret:camunda-mgmt-oidc-connectors-emea-client-secret-AbCdEf"
  client_secrets_kms_key_arn      = "arn:aws:kms:eu-west-1:111111111111:key/00000000-0000-0000-0000-000000000000"
}
