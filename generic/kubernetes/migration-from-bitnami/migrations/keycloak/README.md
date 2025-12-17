# Keycloak Migration: Bitnami → Keycloak Operator (+ CNPG/Managed PostgreSQL)

This guide migrates Keycloak from Bitnami Helm sub-chart to the Keycloak Operator,
and optionally migrates its PostgreSQL database to CloudNativePG or a Managed Service.

## Alignment with Camunda Documentation

Keycloak's PostgreSQL database is backed up using standard `pg_dump`/`pg_restore` procedures.
This is consistent with the overall Camunda backup strategy where component-specific data
in PostgreSQL is handled via PostgreSQL native tools.

**Key considerations from Camunda docs:**
- Keycloak must be **stopped** during database restore
- Use the **same or later** PostgreSQL version for the target database
- Consider exporting realm data as additional backup (Keycloak Admin Console)
- Custom themes/SPI providers need manual migration verification

## Components Affected

- **Keycloak** - Identity and access management
- **Camunda Identity** - Uses Keycloak for authentication
- **PostgreSQL** (if integrated) - Keycloak database

## Migration Scenarios

### Scenario A: Integrated PostgreSQL (Bitnami)

Keycloak uses the Bitnami PostgreSQL sub-chart (`keycloak-postgresql` StatefulSet exists).

**What gets migrated:**
- Keycloak application → Keycloak Operator
- PostgreSQL database → CloudNativePG **OR** Managed Service (RDS/Azure/etc.)

### Scenario B: External PostgreSQL

Keycloak uses an external PostgreSQL (managed separately, no `keycloak-postgresql` StatefulSet).

**What gets migrated:**
- Keycloak application → Keycloak Operator
- PostgreSQL database → **Unchanged** (continues using external DB)

## Prerequisites

1. Base environment configured: `source ../../0-set-environment.sh`
2. Prerequisites validated: `../../1-prerequisites/check-prerequisites.sh`
3. Keycloak Operator deployed: `../../2-deploy-operators/deploy-keycloak-operator.sh`
4. (If Scenario A with Operator target) CNPG operator deployed: `../../2-deploy-operators/deploy-cnpg.sh`

## Migration Steps

### Step 0: Introspect Current Installation

```bash
./0-introspect.sh
```

This will detect:
- Current Keycloak image (including private registry)
- PostgreSQL mode: **integrated** or **external**
- ImagePullSecrets for private registries
- Storage class and size (if integrated PostgreSQL)
- Resource limits and requests
- **Custom volumes/mounts** (Themes, SPIs) - Warns if found

### Step 1: Backup Keycloak Data

```bash
./1-backup.sh
```

- Exports Keycloak realm configuration (JSON)
- **If PG_MODE=integrated**: Backs up PostgreSQL with pg_dump

### Step 2: Deploy Target Infrastructure

```bash
./2-deploy-target.sh
```

**Interactive prompts for target selection:**
- Deploy PostgreSQL Operator (CNPG)?
- Or connect to Managed Service (RDS/Azure)?

Based on selection:
- Creates CNPG cluster using introspected config, **OR**
- Validates connection to user-provided Managed Service
- Deploys Keycloak Operator instance

### Step 3: Freeze Keycloak and Identity

```bash
./3-freeze.sh
```

Scales down:
- Keycloak deployment (saves replica count)
- Camunda Identity deployment (depends on Keycloak)
- **If PG_MODE=integrated**: Performs final backup sync

### Step 4: Restore Data to Target

```bash
./4-restore.sh
```

- **If PG_MODE=integrated**: Restores PostgreSQL to target (CNPG or Managed)
- Imports Keycloak realm to new operator instance

### Step 5: Cutover Helm Release

```bash
./5-cutover.sh
```

Updates Camunda Helm values to:
- Disable Bitnami Keycloak
- **If PG_MODE=integrated**: Disable Bitnami PostgreSQL
- Configure Identity to use Keycloak Operator
- Helm upgrade

### Step 6: Validate and Show Cleanup Commands

```bash
./6-validate.sh
```

Validates:
- Keycloak connectivity
- Identity authentication
- Realm data integrity

Shows cleanup commands (not executed) for:
- Bitnami Keycloak resources
- **If PG_MODE=integrated**: Bitnami PostgreSQL resources

## Rollback

If migration fails at any point:

```bash
./rollback.sh
```

## Estimated Downtime

| Scenario | Data Size | Estimated Downtime |
|----------|-----------|-------------------|
| External PostgreSQL | N/A | 5-10 minutes |
| Integrated < 1GB | < 1GB | 10-15 minutes |
| Integrated 1-5GB | 1-5GB | 15-30 minutes |
| Integrated > 5GB | > 5GB | 30+ minutes |

## Customizations Warning

If the introspection detects **custom volumes** (Themes, SPI providers):

```
⚠ Custom volumes detected! You may need to:
  1. Copy theme files to a location accessible by the new Keycloak pod
  2. Update the Keycloak CRD with appropriate volume mounts
  3. Rebuild custom SPI JARs for Keycloak Operator compatibility
```

These require manual intervention as the Keycloak Operator CRD uses a different configuration approach.

## Files Generated

| File | Purpose |
|------|---------|
| `.state/keycloak.env` | Introspection results |
| `.state/postgres.env` | PostgreSQL introspection (if integrated) |
| `.state/keycloak-realm-backup.json` | Realm export |
| `.state/keycloak-db-backup.sql` | Database backup (if integrated) |
| `.state/keycloak-operator.yml` | Generated Keycloak CRD |
| `.state/cnpg-cluster.yml` | Generated CNPG cluster (if applicable) |
