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
