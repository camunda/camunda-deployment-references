prefix = "camunda-mgmt"

# The management plane has no Orchestration Cluster of its own: no database user for one.
db_seed_iam_usernames = []

# One database for each component. IAM authentication needs no password. The OIDC provider
# connects with a password, which the storage layer generates and stores in Secrets Manager.
databases = {
  oidc_provider = {
    database_name = "oidc_provider"
    username      = "oidc_provider"
    auth          = "password"
  }
  management_identity = {
    database_name = "management_identity"
    username      = "management_identity"
  }
  camunda_hub = {
    database_name = "camunda_hub"
    username      = "camunda_hub"
  }
}
