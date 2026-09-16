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
enable_camunda_hub_authorization = true

# Camunda Hub is deliberately left off here.
#
# Turning it on would plan the ~1600 lines the flag gates, which is the better coverage,
# but this fixture is the only one the golden job compares: enabling the Hub means the
# flag-off plan is no longer verified, and "Hub disabled changes nothing" is the property
# the conditional port list and the count gating exist to guarantee.
#
# Covering both needs a second fixture, which the tooling cannot express today: the
# regeneration recipe hardcodes -var-file=test/golden/golden.tfvars, and the shared
# comparison action hardcodes the golden and compare directories plus the artifact name.
# Tracked in camunda/team-infrastructure-experience#1259, along with the alternative of
# giving Camunda Hub its own root module. Until then the Hub path is covered by the
# module tests and the end-to-end run recorded on the pull request.
