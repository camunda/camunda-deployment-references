# Keycloak Database Configuration (CI/Test only)
#
# This file adds Keycloak database configuration to the base db.tf
# Copy this file to the root when using embedded Keycloak instead of external OIDC

locals {
  # Keycloak-specific database configuration
  camunda_database_keycloak    = "camunda_keycloak" # Name of your camunda database for Keycloak
  camunda_keycloak_db_username = "keycloak_db"      # Username for connection to the DB on Keycloak db
  camunda_keycloak_db_password = "secretvalue%24"   # Replace with a password for connection to the DB on Keycloak db
}
