# ECS single-region (Fargate) – Camunda 8 reference architecture

This folder describes the IaC of Camunda on AWS ECS Fargate in a single-region setup.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/next/self-managed/deployment/containers/cloud-providers/amazon/aws-ecs/

## Authentication modes

The `authentication_mode` input (in `terraform/cluster`) selects how the platform authenticates:

- `basic` (default) — Orchestration Cluster and Connectors use built-in basic-auth users. Keycloak and Management Identity are still deployed so the stack can be flipped to `keycloak` without adding infrastructure.
- `keycloak` — Full OIDC against the bundled Keycloak `camunda-platform` realm that Management Identity bootstraps. Keycloak is exposed on the shared ALB for the browser login redirect.
- `external` — Bring-your-own OIDC provider (Entra ID, Okta, …). Keycloak is not deployed; components point at `var.external_oidc`.

### ⚠️ `keycloak` mode over plain HTTP requires one extra step

This reference exposes the shared ALB over **plain HTTP** by default (no domain, no certificate). Keycloak provisions the `camunda-platform` realm with its default `sslRequired = external`, which **rejects the OIDC discovery/login flow over HTTP with `"HTTPS required"`**. A fresh `authentication_mode = keycloak` apply therefore deploys cleanly but the **browser login will not complete** until one of the following is done:

1. **Serve the ALB over TLS (recommended).** Set `var.alb_certificate_arn` to an ACM certificate. This adds the HTTPS `:443` listener, redirects HTTP → HTTPS, and sets `KC_PROXY_HEADERS=xforwarded` on Keycloak so the ALB's `X-Forwarded-Proto: https` satisfies the realm's `sslRequired` — **no manual step and no `sslRequired` relaxation needed**.
2. **Relax `sslRequired` for an HTTP-only demo.** After the realm is bootstrapped, set the `camunda-platform` realm's `sslRequired` to `NONE` via the Keycloak admin API (or the admin console). This is a demo-only workaround and must not be used for anything reachable outside the VPC.

`basic` and `external` modes are unaffected: `basic` performs no browser OIDC redirect against Keycloak, and `external` relies on the customer's own HTTPS provider.

## Camunda Hub (Web Modeler) — optional

Camunda Hub (Web Modeler + Console) is available behind the `enable_camunda_hub`
flag (default `false`). It deploys one ECS task with two containers
(`camunda/hub` + `camunda/hub-websockets`) served under `/hub` (and `/hub-ws`
for the websocket relay), using a dedicated `camunda-hub` database on the shared
Aurora cluster.

Camunda Hub authenticates via OIDC, so it **requires `authentication_mode =
"oidc"`** — it cannot run under `basic` (enforced by a precondition). Enabling
`enable_camunda_hub` automatically registers the `web-modeler` client (with the
`web-modeler-api` / `web-modeler-public-api` audiences) in the bundled Keycloak
realm; the same HTTP/TLS caveat as above applies to the Web Modeler browser login.

A Camunda license is **optional** — leave `camunda_license_key` empty to run
Camunda Hub in its trial mode (fine for tests); set it to store the key in
Secrets Manager and inject it as `CAMUNDA_LICENSE_KEY`.

The default images (`camunda/hub`, `camunda/hub-websockets`) pull from public
Docker Hub without credentials. To use the private enterprise images, point
`camunda_hub_restapi_image` / `camunda_hub_websockets_image` at
`registry.camunda.cloud/...` and set `registry_username` / `registry_password`;
registry credentials are attached only when an image targets that private
registry.
