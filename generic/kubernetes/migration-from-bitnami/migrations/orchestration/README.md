# Orchestration Migration: Elasticsearch → ECK

This guide migrates Elasticsearch from Bitnami Helm sub-chart to Elastic Cloud on Kubernetes (ECK).

## ⚠️ Important: Migration vs Backup/Restore

This migration procedure is designed for **infrastructure migration** (Bitnami → ECK Operator),
not for production backup/restore scenarios.

**Key differences from [Camunda's official backup/restore procedure](https://docs.camunda.io/docs/self-managed/operational-guides/backup-restore/backup/):**

| Aspect | Official Backup/Restore | This Migration |
|--------|------------------------|----------------|
| **Purpose** | Hot backup during production | Cold migration with planned downtime |
| **Zeebe Partitions** | Backed up to S3/GCS/Azure | PVCs preserved (not migrated) |
| **Approach** | Component-by-component with consistent backupId | Elasticsearch snapshot only |
| **Downtime** | Minimal (hot backup) | Required (freeze before final backup) |

**For production backup/restore**, follow the official Camunda documentation which includes:
1. Soft pause Zeebe exporting (`POST /actuator/exporting/pause?soft=true`)
2. Backup Web Apps via `/actuator/backupHistory`
3. Backup Optimize via `/actuator/backups`
4. Backup Zeebe records indices separately
5. Backup Zeebe partitions via `/actuator/backupRuntime`
6. Resume exporting

## Components Affected

- **Zeebe** - Uses Elasticsearch for process data export
- **Operate** - Uses Elasticsearch for operational data
- **Tasklist** - Uses Elasticsearch for task data
- **Optimize** - Uses Elasticsearch for analytics data

## Prerequisites

1. Base environment configured: `source ../../0-set-environment.sh`
2. Prerequisites validated: `../../1-prerequisites/check-prerequisites.sh`
3. ECK operator deployed: `../../2-deploy-operators/deploy-eck.sh`

## Migration Steps

### Step 0: Introspect Current Installation

```bash
./0-introspect.sh
```

This will detect:
- Current Elasticsearch image (including private registry)
- ImagePullSecrets for private registries
- Storage class and size
- Resource limits and requests
- JVM settings

### Step 1: Backup Elasticsearch Data

```bash
./1-backup.sh
```

Creates a snapshot of all indices using the Elasticsearch snapshot API.

### Step 2: Deploy ECK Elasticsearch Cluster

```bash
./2-deploy-target.sh
```

Deploys an ECK-managed Elasticsearch cluster using the introspected configuration.

### Step 3: Freeze Camunda Components

```bash
./3-freeze.sh
```

Scales down Zeebe exporters and Camunda apps to stop writes to Elasticsearch.

### Step 4: Restore Data to ECK Cluster

```bash
./4-restore.sh
```

Restores the snapshot to the new ECK-managed cluster.

### Step 5: Cutover Helm Release

```bash
./5-cutover.sh
```

Updates Camunda Helm values to point to the ECK cluster and upgrades the release.

### Step 6: Validate and Show Cleanup Commands

```bash
./6-validate.sh
```

Validates the migration and shows cleanup commands for Bitnami resources.

## Rollback

If migration fails at any point:

```bash
./rollback.sh
```

## Estimated Downtime

| Data Size | Estimated Downtime |
|-----------|-------------------|
| < 10GB | 10-15 minutes |
| 10-50GB | 20-45 minutes |
| > 50GB | 60+ minutes |

## Technical Notes

### What This Migration Does

1. **Elasticsearch indices** are migrated via snapshot/restore
2. **Zeebe data** (partitions) is **NOT migrated** - the Zeebe PVCs are preserved
3. **Index templates** are recreated when Camunda components restart

### Zeebe Considerations

Zeebe stores data in two places:
- **Elasticsearch** (`zeebe-record-*` indices) - exported data for Operate/Tasklist
- **Local PVCs** (partitions) - process state, in-flight instances

This migration only moves the Elasticsearch data. Zeebe PVCs remain attached to the
existing StatefulSet and are not affected by the ECK migration.

If you need to migrate Zeebe partitions (e.g., to different storage), that requires
a separate procedure using Zeebe's backup/restore mechanism.

### Compatibility with Camunda 8.8+

As of Camunda 8.8, backup endpoints changed:
- Web Apps: `/actuator/backupHistory` (was `/actuator/backups`)
- Zeebe: `/actuator/backupRuntime` (was `/actuator/backups`)

This migration uses direct Elasticsearch snapshot API, which remains unchanged.
