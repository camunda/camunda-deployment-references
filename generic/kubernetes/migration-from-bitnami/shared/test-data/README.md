# Migration Test Data

This directory contains scripts and resources to generate test data before migration
and validate that data was correctly preserved after migration.

## Overview

When testing the migration from Bitnami sub-charts to operator-based components,
it's important to verify that all data is correctly preserved. These scripts help:

1. **Generate test data** before migration (processes, instances, user tasks)
2. **Validate test data** after migration (check indices, databases, instances)

## Data Generation Modes

### Benchmark Mode (Default) - Recommended for Orchestration

Uses [camunda-8-benchmark](https://github.com/camunda-community-hub/camunda-8-benchmark)
Docker image to generate realistic test data:

- Deploys `typical_process` with 10 service tasks
- Creates process instances at a configurable rate (default: 5/s)
- Auto-completes jobs to populate Elasticsearch indices
- Runs for a configurable duration (default: 60s)

**Advantages:**
- Realistic workload generation
- Populates all Operate/Tasklist indices
- Easy to configure via environment variables

### ZBCTL Mode - For Custom Processes

Uses `zbctl` via kubectl exec to deploy custom BPMN processes:

- Deploys BPMN files from the `bpmn/` directory
- Creates instances with user tasks (visible in Tasklist)
- Creates instances with timers (remain active)

**Advantages:**
- Custom process definitions
- Active instances for manual validation
- User tasks visible in Tasklist

## Scripts

### generate-test-data.sh

Generates test data in the Camunda cluster.

**Usage:**
```bash
# Benchmark mode (default)
export CAMUNDA_NAMESPACE=camunda
export CAMUNDA_RELEASE_NAME=camunda
./generate-test-data.sh

# Or with explicit mode
./generate-test-data.sh --mode benchmark --duration 60 --rate 5

# ZBCTL mode
./generate-test-data.sh --mode zbctl
```

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `CAMUNDA_NAMESPACE` | camunda | Kubernetes namespace |
| `CAMUNDA_RELEASE_NAME` | camunda | Helm release name |
| `TEST_DATA_MODE` | benchmark | `benchmark` or `zbctl` |
| `BENCHMARK_DURATION` | 60 | How long to run benchmark (seconds) |
| `BENCHMARK_PI_PER_SECOND` | 5 | Process instances per second |
| `NUM_PROCESS_INSTANCES` | 5 | Instances per process (zbctl mode) |

### validate-test-data.sh

Validates that test data was preserved after migration.

**Usage:**
```bash
export CAMUNDA_NAMESPACE=camunda
export CAMUNDA_RELEASE_NAME=camunda

./validate-test-data.sh
```

## Camunda 8 Benchmark

The benchmark mode uses the [camunda-8-benchmark](https://github.com/camunda-community-hub/camunda-8-benchmark)
project which:

- Starts process instances at a given rate
- Automatically adjusts rate based on backpressure
- Completes tasks in the processes
- Provides metrics via Prometheus

The benchmark is deployed as a Kubernetes Job that runs for the specified duration,
then is automatically cleaned up.

## BPMN Process Definitions (ZBCTL Mode)

Located in `bpmn/`:

| Process | Description | Validation |
|---------|-------------|------------|
| `migration-test-user-task.bpmn` | Simple process with a user task | User task appears in Tasklist |
| `migration-test-timer.bpmn` | Process with 1-hour timer | Instance waits in Operate |
| `migration-test-service-task.bpmn` | Process with service task | Job waiting in Zeebe |

## Workflow Integration

These scripts are integrated into the migration test workflow:

1. **Before migration**: `generate-test-data.sh` creates test data using benchmark
2. **Run migration**: Execute all migration steps
3. **After migration**: `validate-test-data.sh` verifies data integrity

## What Gets Validated

### Elasticsearch (Orchestration)
- Operate indices exist
- Tasklist indices exist
- Process definitions are indexed
- Process instances are searchable

### PostgreSQL (Identity)
- Database tables exist
- Data is accessible

### PostgreSQL (WebModeler)
- Database tables exist
- Projects/data preserved

### Keycloak
- Pod is running and ready
- Can respond to requests

## Troubleshooting

### Benchmark job fails to start
- Check image pull secrets
- Verify Zeebe gateway service name
- Review job logs: `kubectl logs job/migration-test-data-generator -n camunda`

### Validation fails after migration
- Wait for pods to be fully ready
- Check ECK Elasticsearch credentials
- Verify CNPG clusters are operational
- Review pod logs for errors

### Cannot find test marker
- Test data generation may have failed
- Run `generate-test-data.sh` again before migration
