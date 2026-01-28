# WebModeler Migration: PostgreSQL → CNPG or Managed Service

This guide migrates the WebModeler PostgreSQL database from Bitnami Helm sub-chart
to CloudNativePG Operator or a Managed PostgreSQL Service (RDS, Azure, etc.).

## Alignment with Camunda Documentation

This migration follows the [official Camunda backup/restore guide for Web Modeler](https://docs.camunda.io/docs/self-managed/operational-guides/backup-restore/backup/):

> To create a Web Modeler data backup, refer to the official PostgreSQL documentation
> to back up the database that Web Modeler uses.
>
> For example, to create a backup of the database using `pg_dumpall`, use the following command:
> ```
> pg_dumpall -U <DATABASE_USER> -h <DATABASE_HOST> -p <DATABASE_PORT> -f dump.psql --quote-all-identifiers
> ```

**Key notes from Camunda docs:**
- Use `pg_dump` or `pg_dumpall` for PostgreSQL backups
- Dumps can only be restored into a database with the same or later PostgreSQL version
- Ensure Web Modeler is **stopped** before restoring
- OIDC user IDs must remain consistent between backup and restore

## Components Affected

- **WebModeler** - Web-based process modeling tool
  - RestAPI (database connection)
  - Webapp (frontend)
  - WebSockets (real-time collaboration)
- **PostgreSQL** - WebModeler database

## Skip Conditions

This migration will be **automatically skipped** if:
1. WebModeler component is not deployed (no `webmodeler-webapp` or `webmodeler-restapi` deployment)
2. WebModeler uses external PostgreSQL (no `webmodeler-postgresql` StatefulSet)

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
- Check if WebModeler is deployed (webapp, restapi, or websockets)
- Check if using Bitnami PostgreSQL (vs external)
- Detect PostgreSQL image (including private registry)
- Extract ImagePullSecrets, storage, resources
- Detect PostgreSQL version for compatibility check

**If skipped**, all subsequent scripts will exit gracefully.

### Step 1: Backup WebModeler Database

```bash
./1-backup.sh
```

Creates a pg_dump backup of the web-modeler database using introspected image.

### Step 2: Deploy Target PostgreSQL

```bash
./2-deploy-target.sh
```

**Interactive prompts:**
- Deploy CNPG Operator cluster?
- Or connect to Managed Service (RDS/Azure)?

### Step 3: Freeze WebModeler Components

```bash
./3-freeze.sh
```

Scales down all WebModeler deployments (restapi, webapp, websockets) and creates final backup sync.

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
| `.state/webmodeler.env` | Introspection results |
| `.state/skip` | Skip flag (if migration not needed) |
| `.state/webmodeler-db-backup.dump` | Database backup |
| `.state/cnpg-cluster.yml` | Generated CNPG cluster (if applicable) |
