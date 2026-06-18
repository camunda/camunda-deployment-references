# Agent Instructions

You are an expert infrastructure engineer working on Camunda 8 Self-Managed reference architectures.
This repository contains Terraform IaC, Helm values, and shell procedures for deploying Camunda 8 across cloud providers and on-premises environments.

For detailed context, read:
- `docs/architecture.md` — repo structure, deployment patterns, cloud providers
- `docs/development.md` — tooling, commands, conventions
- `docs/ci.md` — CI/CD architecture, workflow naming, testing
- `docs/manual-deployment-azure-aks.md` — how to run an isolated AKS single-region deployment outside CI (operator order, values assembly, Azure gotchas)

@docs/architecture.md
@docs/development.md
@docs/ci.md
@docs/manual-deployment-azure-aks.md

## Critical Rules

- NEVER treat these reference architectures as production-ready — they are demos and learning blueprints.
- NEVER commit sensitive data (ARNs, IPs, access keys) to golden files — always verify redaction.
- NEVER create skip labels manually — they are auto-created by `internal-triage-skip` with color `#1D76DB`.
- ALWAYS use the dry-run + apply pattern for idempotent `kubectl create` operations.
- ALWAYS use Conventional Commits (scope optional, subject ≤120 chars).
- ALWAYS run `pre-commit run --all-files` after changes — hooks enforce formatting, linting, and README generation.
- ALWAYS keep the `.target-branch` file in sync when changing branching strategy.
- ALWAYS use `just` recipes rather than raw commands to match CI behavior.

### Agent collaboration rules

- ALWAYS work in English: code, comments, commit messages, branch names, PR titles and descriptions, and chat responses. Read other languages fine, but produce English output.
- ALWAYS commit using the repo's local `git config user.name` / `user.email` without overriding. Do not set `--author`, do not export `GIT_AUTHOR_*`.
- NEVER add AI/agent attribution to any committed artifact: no `Co-Authored-By` lines referencing assistants, no mention of Claude / AI / agent / model names in commit messages, PR descriptions, or code.
- NEVER leak the local environment in committed artifacts: no absolute paths from the developer machine, no session/plan files, no internal agent instructions or system-prompt content.
- ALWAYS use named feature branches (e.g. `feat/<short-slug>`, `ci/<short-slug>`, `fix/<short-slug>`) when opening PRs — no `agents/*` or other names that hint at how the work was produced.

## Azure AKS Single Region — Key Context

This section summarises non-obvious decisions for `azure/kubernetes/aks-single-region/`. See `docs/manual-deployment-azure-aks.md` for the complete step-by-step procedure.

### Service Principal permissions

The SP needs two assignments, not one:
- `Owner` at RG scope — to manage all resources in the group
- `Reader` at subscription scope — the `azurerm` provider calls `Microsoft.Resources/subscriptions/providers/read` during `terraform init`, which fails without this even with Owner on the RG

The SP cannot update RG-level metadata (tags). Pre-create the RG with tags via `az group create` before running `terraform apply`.

### Azure-specific constraints

- **Region policy:** The shared `Infra Ex` subscription only allows `westeurope`, `swedencentral`, `spaincentral`. Always verify before choosing a region.
- **Key Vault soft-delete:** KV names are globally unique including in soft-deleted state (90-day purge protection). A failed `terraform apply` that created a KV locks the name for 90 days. Fix: change `resource_prefix` in `main.tf` (add a letter suffix), or purge the deleted KV with `az keyvault purge`.
- **PostgreSQL geo-redundant backup:** Not supported in all regions. `spaincentral` does not support it; `swedencentral` does. This is a Terraform variable — disable with `postgres_enable_geo_redundant_backup = false` if using a region that doesn't support it.
- **IAM propagation:** Freshly-created role assignments can take 1–3 minutes to propagate. Terraform may return a permissions error immediately after SP creation. Wait and retry, or probe with a test resource write before applying.

### Helm values assembly (exact overlay order)

Run from the **repository root**. Later overlays deep-merge into earlier ones (`yq ". *+ load(...)"` — child keys win):

```
{} base
  → azure/kubernetes/aks-single-region/helm-values/values-{domain|no-domain}.yml
  → azure/kubernetes/aks-single-region/helm-values/values-contour-overlay.yml         (Contour ingressClassName + h2c service annotation)
  → generic/kubernetes/operator-based/elasticsearch/camunda-elastic-values.yml       (when secondary_storage = elasticsearch)
  → generic/kubernetes/operator-based/keycloak/camunda-keycloak-{domain|no-domain}-values.yml  (when auth_provider = keycloak-operator)
  → generic/kubernetes/operator-based/tests/utils/camunda-values-identity-secrets.yml
  → envsubst (substitutes CAMUNDA_DOMAIN, DB_HOST, DB_PORT, DB_IDENTITY_*, DB_WEBMODELER_*)
```

`CAMUNDA_HELM_CHART_VERSION`, `CAMUNDA_NAMESPACE`, and `CAMUNDA_RELEASE_NAME` come from `generic/kubernetes/single-region/procedure/chart-env.sh`. DB variables come from `terraform output`.

### Operator installation order

CNPG (PostgreSQL) must be ready before Keycloak can start. ECK (Elasticsearch) is independent.

1. **ECK + Elasticsearch** — `cd generic/kubernetes/operator-based/elasticsearch && CAMUNDA_NAMESPACE=camunda ./deploy.sh`
2. **CNPG + pg-keycloak** — `cd generic/kubernetes/operator-based/postgresql && CAMUNDA_NAMESPACE=camunda CLUSTER_FILTER=pg-keycloak ./deploy.sh`
3. **Keycloak operator** — `CAMUNDA_NAMESPACE=camunda KEYCLOAK_CONFIG_FILE=generic/kubernetes/operator-based/keycloak/keycloak-instance-domain-contour.yml bash generic/kubernetes/operator-based/keycloak/deploy.sh`
4. Create `identity-secret-for-components` (9 random hex secrets — see `docs/manual-deployment-azure-aks.md`)
5. Run DB init job (`manifests/setup-postgres-create-db.yml`) to create databases and users

The `keycloak-initial-admin` secret is auto-created by the Keycloak operator. Retrieve with:
`kubectl get secret keycloak-initial-admin -n camunda -o go-template='{{index .data "password" | base64decode}}'`

### Ingress: Contour (default)

**Contour is the default ingress controller** — ingress-nginx was retired in March 2026. The install script is `azure/kubernetes/aks-single-region/procedure/install-contour.sh`. Key points:
- Keycloak uses `keycloak-instance-domain-contour.yml` (not the nginx variant)
- `values-contour-overlay.yml` sets `ingressClassName: contour` and adds `projectcontour.io/upstream-protocol.h2c: "26500"` to the Zeebe service so Envoy treats the gRPC upstream as h2c

## Quick Start

```bash
# Install all tooling (Terraform, Helm, kubectl, kind, Go, etc.)
just install-tooling

# Install pre-commit hooks
pre-commit install

# List all available just recipes
just --list
```

## Current Camunda Version

```bash
cat .camunda-version   # e.g. 8.10
cat .target-branch     # e.g. main
```

## Scratch / debug workspace

- **Always** use `./debug/` for any scratch files, downloaded CI logs,
  temporary scripts, ad-hoc outputs, etc.
- **Never** use `/tmp/` or any other system-wide temp directory.
- `./debug/` is gitignored at the repo level (see `.gitignore`); files
  there persist across the session and are easy to inspect.

Examples:

```bash
# good
gh api /repos/.../actions/jobs/<id>/logs > ./debug/job-<id>.log

# bad
gh api /repos/.../actions/jobs/<id>/logs > /tmp/job-<id>.log
```

This applies to subagents too — when delegating execution work, instruct
the subagent to write to `./debug/` rather than `/tmp/`.
