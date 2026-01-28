# Keycloak Database Outputs (CI/Test only)
#
# This file adds Keycloak database outputs to the base outputs.tf
# Copy this file to the root when using embedded Keycloak instead of external OIDC

output "camunda_database_keycloak" {
  value = local.camunda_database_keycloak
}

output "camunda_keycloak_db_username" {
  value = local.camunda_keycloak_db_username
}

output "camunda_keycloak_db_password" {
  value     = local.camunda_keycloak_db_password
  sensitive = true
}
