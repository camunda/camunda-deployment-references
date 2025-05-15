locals {
  resource_prefix     = var.resource_prefix_placeholder # Change this to a name of your choice
  resource_group_name = ""                              # Change this to a name of your choice, if not provided, it will be set to resource_prefix-rg, if provided, it will be used as the resource group name
  location            = "swedencentral"                 # Change this to your desired Azure region
  # renovate: datasource=endoflife-date depName=azure-kubernetes-service versioning=loose
  kubernetes_version = "1.31" # Change this to your desired Kubernetes version (aks - major.minor)

  db_admin_username = "secret_user"    # Replace with your Aurora username
  db_admin_password = "secretvalue%23" # Replace with your Aurora password, password must contain at least one letter, one number, and one special character.

  camunda_database_keycloak   = "camunda_keycloak"   # Name of your camunda database for Keycloak
  camunda_database_identity   = "camunda_identity"   # Name of your camunda database for Identity
  camunda_database_webmodeler = "camunda_webmodeler" # Name of your camunda database for WebModeler

  # Connection configuration
  camunda_keycloak_db_username   = "keycloak_db"   # This is the username that will be used for connection to the DB on Keycloak db
  camunda_identity_db_username   = "identity_db"   # This is the username that will be used for connection to the DB on Identity db
  camunda_webmodeler_db_username = "webmodeler_db" # This is the username that will be used for connection to the DB on WebModeler db

  camunda_keycloak_db_password   = "secretvalue%24" # Replace with a password that will be used for connection to the DB on Keycloak db
  camunda_identity_db_password   = "secretvalue%25" # Replace with a password that will be used for connection to the DB on Identity db
  camunda_webmodeler_db_password = "secretvalue%26" # Replace with a password that will be used for connection to the DB on WebModeler db
}
