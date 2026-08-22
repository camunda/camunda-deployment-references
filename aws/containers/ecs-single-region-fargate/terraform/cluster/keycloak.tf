# Bundled Keycloak — the default OIDC provider shipped with this reference.
#
# Deployed only when OIDC is enabled AND no external provider is supplied
# (local.deploy_bundled_keycloak). It self-provisions the `camunda-platform` realm
# via Keycloak's realm import (see keycloak_realm.tf) and then simply feeds the
# generic local.oidc interface — so the platform components treat it exactly like an
# external OIDC provider and never reference Keycloak directly.

module "keycloak" {
  source = "../../../../modules/ecs/fargate/keycloak"

  count = local.deploy_bundled_keycloak ? 1 : 0

  depends_on = [null_resource.run_db_seed_task]

  prefix                      = "${var.prefix}-oc1"
  ecs_cluster_id              = aws_ecs_cluster.ecs.id
  vpc_id                      = module.vpc.vpc_id
  vpc_private_subnets         = module.vpc.private_subnets
  aws_region                  = data.aws_region.current.region
  s2s_cloudmap_namespace      = module.orchestration_cluster.s2s_cloudmap_namespace
  log_group_name              = module.orchestration_cluster.log_group_name
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
  registry_credentials_arn    = join("", aws_secretsmanager_secret.registry_credentials[*].arn)

  # The browser must reach Keycloak through the shared ALB for the login redirect,
  # so the /auth* rule is always enabled for the bundled provider.
  alb_listener_http_webapp_arn         = local.webapp_listener_arn
  enable_alb_http_webapp_listener_rule = true

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]

  environment_variables = concat([
    { name = "KC_DB", value = "postgres" },
    { name = "KC_DB_URL", value = "jdbc:postgresql://${module.postgresql.aurora_endpoint}:5432/${var.keycloak_db_name}" },
    { name = "KC_DB_USERNAME", value = var.keycloak_db_username },
    { name = "KC_BOOTSTRAP_ADMIN_USERNAME", value = var.keycloak_admin_username },
    { name = "KC_HTTP_ENABLED", value = "true" },
    { name = "KC_HTTP_PORT", value = "18080" },
    { name = "KC_HTTP_RELATIVE_PATH", value = "/auth" },
    { name = "KC_HEALTH_ENABLED", value = "true" },
    # hostname-strict=false lets Keycloak derive its frontend URL (and token `iss`)
    # from the request host. Every actor (browser, orchestration discovery,
    # connectors) reaches Keycloak via the shared ALB, so `iss` is consistently the
    # ALB URL without pinning KC_HOSTNAME. Production behind TLS would instead pin
    # KC_HOSTNAME + KC_PROXY_HEADERS=xforwarded.
    { name = "KC_HOSTNAME_STRICT", value = "false" },
    { name = "KC_TRANSACTION_XA_ENABLED", value = "false" },
    # Single-instance deployment (task_desired_count = 1): use the local cache so
    # Keycloak does not form a JGroups/Infinispan cluster. Otherwise a rolling
    # redeploy briefly runs two tasks that cannot reach each other on the JGroups
    # ports (7800/57800, not opened in the intra-VPC SG); the new node's cluster
    # health check stays DOWN and the ECS circuit breaker fails the deployment.
    { name = "KC_CACHE", value = "local" },
    ],
    # When the ALB terminates TLS (var.alb_certificate_arn set), trust its
    # X-Forwarded-* headers so Keycloak sees the request as HTTPS and the realm's
    # default sslRequired=external is satisfied without manual relaxation. Off in
    # the HTTP demo.
    local.alb_https_enabled ? [
      { name = "KC_PROXY_HEADERS", value = "xforwarded" },
  ] : [])

  secrets = [
    { name = "KC_DB_PASSWORD", valueFrom = aws_secretsmanager_secret.keycloak_db_password[0].arn },
    { name = "KC_BOOTSTRAP_ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.keycloak_admin_password[0].arn },
    # The camunda-platform realm (clients + admin user, with their secrets) is
    # imported on startup from this JSON — Keycloak self-provisions the realm.
    { name = "KEYCLOAK_REALM_IMPORT_JSON", valueFrom = aws_secretsmanager_secret.keycloak_realm_import[0].arn },
  ]

  # Write KEYCLOAK_REALM_IMPORT_JSON to the import dir and start with --import-realm.
  enable_realm_import = true

  task_desired_count          = 1
  wait_for_steady_state       = true
  extra_task_role_attachments = []
}
