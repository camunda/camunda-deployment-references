# Variables for golden-plan generation.
#
# Exercise OIDC mode with the bundled Keycloak (external_oidc unset) so the golden
# covers the full auth surface this reference adds: the Keycloak service + realm
# import, Management Identity, and all OIDC wiring. The `basic` default deploys none
# of that, so testing `oidc` here gives meaningful regression coverage.
authentication_mode = "oidc"

# Seed Management Identity's authorization model too, so the golden plan exercises that
# code path on every run. Note this does NOT pin the rendered SPRING_APPLICATION_JSON
# document: the AWS provider marks `container_definitions` sensitive, so every task
# definition's env vars are redacted out of the golden. What CI catches here is a broken
# expression or a regressed precondition, not a change in the presets or mapping rule —
# those are covered by the end-to-end test.
enable_web_modeler_authorization = true

# Plan Camunda Hub too. The flag gates roughly 1600 lines -- a module, its ALB rules and
# target groups, the Keycloak client, the dedicated database and the IAM policy -- none of
# which any tfvars turned on, so CI only ever planned the flag-off path. A plan is cheap
# and catches the class of bug the module tests cannot: an ECS service that references a
# target group no listener rule attaches, a precondition that regressed, or an expression
# that only evaluates when the Hub exists.
#
# Requires enable_web_modeler_authorization above, which a precondition enforces.
enable_camunda_hub = true
