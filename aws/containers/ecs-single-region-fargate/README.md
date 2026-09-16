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

> **Enable this on a new cluster, not an existing one.** Keycloak imports the realm only
> when that realm does not yet exist (`kc.sh start --import-realm`), and the `web-modeler`
> client lives in that import. Turning `enable_camunda_hub` on against a deployment whose
> realm already exists therefore applies cleanly and still leaves Keycloak with no client
> for the Hub, so the browser login cannot complete and nothing in the plan warns about it.
> Either deploy the flag from the start, or register the client out of band (for example a
> one-shot `kcadm` task) before enabling it.

> **The authorization seed only applies to an Identity that has not been initialized.**
> Management Identity persists its mapping rules, and it de-duplicates them on the
> `(claim-name, claim-value, rule-type)` triple rather than on the rule name. An Identity
> that already created its own `Default` rule from `IDENTITY_INITIAL_CLAIM_*` therefore
> keeps it, the declared rule is skipped, and the admin is left with `ManagementIdentity`
> only — so Web Modeler authenticates and every project call is denied. Enabling
> `enable_web_modeler_authorization` on an Identity that has already run needs the
> existing rule removed first; Terraform cannot do it, because the rules live in
> Identity's database rather than in any AWS resource.

A Camunda license is **optional** — leave `camunda_license_key` empty to run
Camunda Hub in its trial mode (fine for tests); set it to store the key in
Secrets Manager and inject it as `CAMUNDA_LICENSE_KEY`.

Changing `camunda_license_key` later updates the Secrets Manager value but does not
restart the Hub: ECS resolves `valueFrom` when a task starts, and the task definition
references the secret by a stable ARN, so the running tasks keep the previous key until
the service is redeployed for some other reason. Force a new deployment to pick it up.

The default images (`camunda/hub`, `camunda/hub-websockets`) pull from public
Docker Hub without credentials. To use the private enterprise images, point
`camunda_hub_restapi_image` / `camunda_hub_websockets_image` at
`registry.camunda.cloud/...` and set `registry_username` / `registry_password`;
registry credentials are attached only when an image targets that private
registry.
