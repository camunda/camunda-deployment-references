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
- **Camunda Hub** (Web Modeler + Console) resolves permissions through Management Identity's RBAC model instead. Identity ships no roles out of the box, so `var.enable_camunda_hub_authorization` (default `false`) seeds them: the component presets declaring the `web-modeler-api` and `web-modeler-public-api` resource servers with their permissions and the `Web Modeler` / `Web Modeler Admin` roles, plus a mapping rule granting those roles to the admin principal by token claim.

  Enable it when a Camunda Hub deployment consumes this Identity. Without it Hub authenticates and reaches Identity successfully, but every authorization check is denied (`403` on the management API, `404` on org-scoped projects) because the roles it asks about do not exist. The flag requires `authentication_mode = "oidc"`.

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
> `enable_camunda_hub_authorization` on an Identity that has already run needs the
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

## Load testing

An optional overlay puts a Prometheus and a load generator next to the cluster,
so it can be watched under load instead of at rest. It is off by default:

```hcl
enable_load_tests = true
```

With the flag false nothing extra is planned, so the plan of this state is
unchanged for anyone who does not ask for it.

```bash
terraform apply -var enable_load_tests=true

# throughput, live
aws logs tail "$(terraform output -raw load_generator_log_group)" --follow

# Prometheus, from inside the VPC
terraform output -raw prometheus_endpoint
```

| Knob | Default | What it changes |
|---|---|---|
| `load_tests_start_rate` | `150` | Process instances started per second |
| `load_tests_retention_time` | `168h` | How far back Prometheus can be queried |
| `load_tests_prometheus_port` | `9090` | Port Prometheus listens on |
| `enable_benchmark_cluster_profile` | `false` | Applies the cluster-side settings the absorbed benchmark ran with |

For numbers comparable with the benchmark this came from, turn on the cluster
profile as well:

```hcl
enable_load_tests                = true
enable_benchmark_cluster_profile = true
```

That adds explicit processing flow control (`WRITE_LIMIT = 10000`) and switches
EFS from elastic to 60 MiB/s provisioned throughput, which is what that
benchmark ran with. It is separate from `enable_load_tests` because both change
how the engine and its storage behave for every workload, not just a benchmark.

> [!IMPORTANT]
> The overlay requires `authentication_mode = "basic"`. The generator runs the
> community benchmark, which this module wires for basic auth only, so enabling
> it alongside `authentication_mode = "oidc"` fails the plan rather than
> deploying a generator that would collect 401s. Tracking the OIDC client
> credential flow is left to whoever needs it.

The generator authenticates as the `admin` user this state already creates, with
the password from Secrets Manager. Prometheus finds the cluster through Cloud Map
rather than a fixed address, so a redeployed cluster is picked up on its own.

Neither piece is exposed publicly. Prometheus answers on its private DNS name,
and the generator has no endpoint at all. Pair it with the
[FIS chaos experiments](../../common/procedure/chaos-fis/README.md) to see what
a broker restart or a lost Availability Zone does to the throughput number.

### Continuous integration

`.github/workflows/aws_ecs_single_region_fargate_load_tests.yml` runs this
overlay every Friday and on any pull request that touches it. It deploys the
cluster with `enable_load_tests = true` at a reduced rate, then fails unless
the number of benchmark instances the cluster itself reports keeps rising —
which is what separates a generator that is running from one that is running
and being ignored.

### Where this came from

The overlay is the part of
[`camunda/camunda-load-tests-ecs`](https://github.com/camunda/camunda-load-tests-ecs)
that made sense here, folded in under
camunda/team-infrastructure-experience#464.
That repository built an ECS Camunda cluster plus load against it, and already
consumed this repository's `ecs/fargate/orchestration-cluster` and `aurora`
modules by commit pin, so most of the overlap was already one-directional.

What came across, and what did not:

| From | Landed as | Why |
|---|---|---|
| `aws/monitoring` | [`modules/ecs/fargate/monitoring`](../../modules/ecs/fargate/monitoring/README.md) | The persistent Prometheus and its Cloud Map discovery, which is the piece worth generalising |
| `aws/load_test` | [`modules/ecs/fargate/load-generator`](../../modules/ecs/fargate/load-generator/README.md) | Rewritten on the public community benchmark; the original pulled private `team-zeebe` images |
| `aws/chaos-tests` | [`common/procedure/chaos-fis`](../../common/procedure/chaos-fis/README.md) | Portable as-is once the account-specific defaults were parameterised |
| `aws/benchmark` | — | An ECS Camunda cluster with Aurora, which is what this reference architecture already is |
| `aws/stable` | — | A shared VPC, ECR and registry credentials read from Camunda's internal Vault, tied to one AWS account and to CIDRs coordinated with a private repository |

The fold tracks upstream `main` at `07888c16`. The only commit there since the
content was taken moves the benchmark workflows' Vault authentication from
AppRole to JWT, and touches neither directory above. One pull request is still
open upstream,
[#6](https://github.com/camunda/camunda-load-tests-ecs/pull/6): it adds a
dual-region stack, and what it changes in `aws/load_test` and `aws/monitoring`
is basic auth, REST addressing and cross-region Prometheus federation. The
first two are already here; the third belongs to a dual-region topology, which
this repository covers with
[`ecs-dual-region-fargate`](../ecs-dual-region-fargate/README.md).

The two dropped states are the ones that only made sense inside Camunda's own
account. `aws/benchmark` would have been a second, worse copy of this state, and
`aws/stable` cannot be copied at all: its registry credentials come from
`vault.int.camunda.com` and its VPC CIDRs have to match what Camunda's network
repository expects. Nothing here needs either. The parts that carried the same
coupling were dropped with them: the GCP federation security group in the
monitoring stack, and the `dev`/`prod` state layout that existed because several
benchmarks shared one account.
