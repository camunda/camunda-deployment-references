# Variables for golden-plan generation.
#
# Exercise OIDC mode with the bundled Keycloak (external_oidc unset) so the golden
# covers the full auth surface this reference adds: the Keycloak service + realm
# import, Management Identity, and all OIDC wiring. The `basic` default deploys none
# of that, so testing `oidc` here gives meaningful regression coverage.
authentication_mode = "oidc"
