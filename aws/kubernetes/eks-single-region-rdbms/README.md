# EKS Single Region — RDBMS Variant

This is the RDBMS variant of the EKS single-region reference architecture.
It uses **Amazon Aurora PostgreSQL** as both the component database and the
**secondary storage** for the orchestration cluster, replacing Amazon OpenSearch.

## Differences from the OpenSearch Variant

| Aspect | OpenSearch (`eks-single-region`) | RDBMS (`eks-single-region-rdbms`) |
|--------|----------------------------------|-----------------------------------|
| Secondary storage | Amazon OpenSearch | Amazon Aurora PostgreSQL |
| Optimize | Enabled | Disabled (requires Elasticsearch/OpenSearch) |
| Orchestration DB | N/A | `camunda_orchestration` database |
| Infrastructure | Aurora + OpenSearch domain | Aurora only (lighter) |

## Shared Files

Most Terraform and procedure files are **symlinked** from `eks-single-region/`
to avoid duplication. Only files that differ for RDBMS are maintained as
separate copies:

- `terraform/cluster/db.tf` — Adds the orchestration database credentials and output
- `terraform/cluster/opensearch.tf` — **Omitted** (no OpenSearch domain is provisioned)
- `helm-values/` — RDBMS-specific Helm values (no OpenSearch, RDBMS secondary storage, Optimize disabled)
- `setup-postgres-create-db.yml` — Creates the additional orchestration database
- `procedure/export-helm-values.sh` — Exports orchestration DB variables (drops OpenSearch)
- `procedure/create-setup-db-secret.sh` — Adds orchestration DB credentials to the setup secret
- `procedure/create-external-db-secrets.sh` — Creates `orchestration-postgres-secret`
- `procedure/check-env-variables.sh` — Validates orchestration DB env vars (drops `OPENSEARCH_HOST`)

## Quick Start

Follow the same procedure as `eks-single-region`, but use this directory instead.
Refer to the [EKS single-region documentation](../eks-single-region/terraform/cluster/README.md)
for the full setup guide.
