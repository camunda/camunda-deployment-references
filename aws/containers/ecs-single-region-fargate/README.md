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
