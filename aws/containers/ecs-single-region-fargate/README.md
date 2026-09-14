# ECS single-region (Fargate) – Camunda 8 reference architecture

This folder describes the IaC of Camunda on AWS ECS Fargate in a single-region setup.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/next/self-managed/deployment/containers/cloud-providers/amazon/aws-ecs/

## Authentication modes

The `authentication_mode` input (in `terraform/cluster`) selects how the platform authenticates:

- `basic` (default) — Orchestration Cluster and Connectors use built-in basic-auth users. No identity provider is deployed: neither the bundled Keycloak nor Management Identity. Fully self-contained.
- `oidc` — OIDC authentication across the platform, plus Management Identity. The provider is selected from `var.external_oidc`:
  - unset (default) — a bundled Keycloak is deployed and self-provisions the `camunda-platform` realm (`kc.sh start --import-realm`), so the reference runs out of the box with no external dependency. It is exposed on the shared ALB for the browser login redirect.
  - set — the customer's own provider (Entra ID, Okta, …) is used and Keycloak is not deployed.

Either way every component consumes a single provider-agnostic OIDC interface and never references Keycloak: the bundled Keycloak is just the default provider we ship, wired exactly like an external one.

### TLS

The shared ALB is plain HTTP by default (no domain, no certificate), so the bundled realm is imported with `sslRequired = none` to keep the browser login flow working. HTTP-only is a demo posture and must not be used for anything reachable outside the VPC.

Serving TLS requires two inputs together:

- `alb_certificate_arn` — an ACM certificate. Adds the HTTPS `:443` listener, redirects HTTP → HTTPS, sets `KC_PROXY_HEADERS=xforwarded` on Keycloak so it derives its frontend URL from the ALB, and switches the realm to `sslRequired = external`.
- `alb_public_hostname` — the DNS name clients actually use, covered by that certificate (an alias record pointing at the ALB). Every OIDC URL is built from this name and the listener's scheme: the issuer, the redirect URI, and the Management Identity base URL. That is what keeps the `iss` the browser is redirected to identical to the one the Orchestration Cluster and Connectors validate.

Neither works alone, and a precondition fails the plan if the certificate is set without the hostname. ACM does not issue certificates for the ALB's own `*.elb.amazonaws.com` name, so TLS on the raw ALB name fails hostname verification — for the browser and equally for the backends that fetch the discovery document and the token.

## Authorization

Authorization is split across two components, and each is seeded independently:

- **Orchestration Cluster** (Zeebe / Operate / Tasklist / v2 API) owns its own authorization. It is seeded Camunda-side via `CAMUNDA_SECURITY_INITIALIZATION_*`, which grants the admin user and the Connectors client their default roles. This is always on.
- **Web Modeler / Camunda Hub** resolves permissions through Management Identity's RBAC model instead. Identity ships no roles out of the box, so `var.enable_web_modeler_authorization` (default `false`) seeds them: the component presets declaring the `web-modeler-api` and `web-modeler-public-api` resource servers with their permissions and the `Web Modeler` / `Web Modeler Admin` roles, plus a mapping rule granting those roles to the admin principal by token claim.

  Enable it when a Web Modeler / Camunda Hub deployment consumes this Identity. Without it Web Modeler authenticates and reaches Identity successfully, but every authorization check is denied (`403` on the management API, `404` on org-scoped projects) because the roles it asks about do not exist. The flag requires `authentication_mode = "oidc"`.

  In the generic OIDC profile Identity cannot read role assignments out of the identity provider, so a claim-based mapping rule is the only way to bind a role to a user. See `terraform/cluster/identity_authorization.tf`.
