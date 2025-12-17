# Identity Migration: PostgreSQL → CNPG or Managed Service

This guide migrates the Identity PostgreSQL database from Bitnami Helm sub-chart
to CloudNativePG Operator or a Managed PostgreSQL Service (RDS, Azure, etc.).

## Alignment with Camunda Documentation

PostgreSQL backup follows standard `pg_dump`/`pg_restore` procedures as recommended
in PostgreSQL documentation. The Identity database does not have a specific backup
API like Operate/Tasklist (which use Elasticsearch), so standard PostgreSQL
backup tools are the correct approach.

**Key considerations:**
- Identity must be **stopped** during restore to prevent data inconsistencies
- Use the **same or later** PostgreSQL version for the target database
- OIDC configuration must remain consistent with Keycloak

## Components Affected

- **Camunda Identity** - Identity and access management for Camunda
- **PostgreSQL** - Identity database

## Skip Conditions

This migration will be **automatically skipped** if:
1. Identity component is not deployed (`identity` deployment not found)
2. Identity uses external PostgreSQL (no `identity-postgresql` StatefulSet)

## Prerequisites

1. Base environment configured: `source ../../0-set-environment.sh`
2. Prerequisites validated: `../../1-prerequisites/check-prerequisites.sh`
3. CNPG operator deployed (if using Operator target): `../../2-deploy-operators/deploy-cnpg.sh`

## Migration Steps

### Step 0: Introspect Current Installation

```bash
./0-introspect.sh
```

This will:
- Check if Identity is deployed
- Check if using Bitnami PostgreSQL (vs external)
- Detect PostgreSQL image (including private registry)
- Extract ImagePullSecrets, storage, resources
- Detect PostgreSQL version for compatibility check

**If skipped**, all subsequent scripts will exit gracefully.

### Step 1: Backup Identity Database

```bash
./1-backup.sh
```

Creates a pg_dump backup of the identity database using introspected image.

### Step 2: Deploy Target PostgreSQL

```bash
./2-deploy-target.sh
```

**Interactive prompts:**
- Deploy CNPG Operator cluster?
- Or connect to Managed Service (RDS/Azure)?

### Step 3: Freeze Identity Component

```bash
./3-freeze.sh
```

Scales down Identity deployment and creates final backup sync.

### Step 4: Restore Data to Target

```bash
./4-restore.sh
```

Restores the database to CNPG or Managed Service using pg_restore.

### Step 5: Cutover Helm Release

```bash
./5-cutover.sh
```

Updates Camunda Helm values to use the new PostgreSQL backend.

### Step 6: Validate and Show Cleanup Commands

```bash
./6-validate.sh
```

Validates connectivity and shows cleanup commands (not executed).

## Rollback

If migration fails at any point:

```bash
./rollback.sh
```

## Estimated Downtime

| Data Size | Estimated Downtime |
|-----------|-------------------|
| < 100MB | 5-10 minutes |
| 100MB-1GB | 10-20 minutes |
| > 1GB | 20+ minutes |

## Files Generated

| File | Purpose |
|------|---------|
| `.state/identity.env` | Introspection results |
| `.state/skip` | Skip flag (if migration not needed) |
| `.state/identity-db-backup.dump` | Database backup |
| `.state/cnpg-cluster.yml` | Generated CNPG cluster (if applicable) |
