# Brainstorm: ECS Dual-Region with RDBMS Secondary Storage

**Date:** 2026-04-08
**Status:** Draft
**Author:** Marcel Dias + Claude

## What We're Building

A dual-region active-active deployment of Camunda 8 on AWS ECS Fargate, using Aurora Global Database (PostgreSQL) as the RDBMS secondary storage backend. This extends the existing `aws/containers/ecs-single-region-fargate/` reference architecture to span two AWS regions.

This will be the **first reference architecture to prove RDBMS secondary storage in a dual-region setup** — the current Camunda docs note it as unsupported, but that reflects a testing gap rather than a technical limitation.

### Goals

- Active-active Zeebe cluster stretched across 2 regions (8 brokers, 4 per region)
- Aurora Global Database for cross-region RDBMS secondary storage replication
- ECS Service Connect + Transit Gateway for cross-region networking
- Route 53 Resolver for cross-region Cloud Map namespace resolution
- No Elasticsearch dependency (pure RDBMS mode)
- Manual failover/failback procedure scripts
- Reference architecture for learning/demonstration (not production)

### Non-Goals (for MVP)

- Identity/Keycloak (phased — start with basic auth, document as known limitation)
- Production-grade SLAs or automated failover
- Cross-region EFS replication
- Optimize (not available in RDBMS mode)

## Why This Approach

### Aurora Global Database + RDBMS Secondary Storage

The existing ECS single-region setup already uses Aurora PostgreSQL with RDBMS secondary storage mode — no Elasticsearch at all. Aurora Global Database extends this naturally:

- **Infrastructure-layer replication** (<1s lag) vs. application-layer dual exporters
- **AWS JDBC Wrapper** already in use, which natively supports failover/reader endpoints
- **Simpler architecture** — no Elasticsearch to manage, no cross-region ES password sync
- **Cost-effective** — one writer region, read replicas in secondary region

This is a fundamentally different approach than the EKS dual-region (which uses dual Elasticsearch exporters). It demonstrates a cleaner, RDBMS-native path.

### Transit Gateway over VPC Peering

- Transitive routing (scales beyond 2 regions if needed)
- Centralized network management
- Better bandwidth and latency characteristics for sustained cross-region traffic
- More production-realistic than 1:1 VPC peering

### Route 53 Resolver + Cloud Map for Cross-Region Discovery

- Cloud Map is region-scoped; Route 53 Resolver forwarding rules bridge namespaces across Transit Gateway
- Each region's Cloud Map namespace (e.g., `region0-oc.service.local`, `region1-oc.service.local`) becomes resolvable from the other region
- Fully AWS-native — no CoreDNS chaining hacks like the EKS dual-region pattern
- Internal NLBs per region expose Zeebe cluster port (26502) for cross-region Raft traffic

### Broker Distribution: Odd/Even Pattern

Per [Camunda dual-region docs](https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/#zeebe-cluster-configuration):

- Even-numbered brokers (0, 2, 4, 6) in region 0
- Odd-numbered brokers (1, 3, 5, 7) in region 1
- Replication factor of **4** ensures data is copied across both regions
- Round-robin partition distribution balances load across regions
- Cluster size must be a multiple of 2 and at least 4

In ECS, this means configuring the S3 node ID provider to assign the correct broker IDs per region (unlike EKS where StatefulSet ordinals handle this via Helm chart logic).

## Key Decisions

1. **Active-active model** — Both regions serve traffic, Zeebe Raft consensus spans regions
2. **Aurora Global Database** — Infrastructure-managed cross-region DB replication; cross-region write latency (~50-100ms for region 1) is acceptable for a reference architecture
3. **Transit Gateway** — Cross-region network connectivity (not VPC peering)
4. **Route 53 Resolver + Cloud Map** — Cross-region service discovery; Route 53 Resolver forwarding rules resolve remote Cloud Map namespaces over Transit Gateway
5. **Internal NLB per region** — Expose Zeebe cluster port (26502) for cross-region Raft consensus
6. **EFS per region (independent)** — Each region has its own EFS; data rebuilt via Raft on failover
7. **No Identity (MVP)** — Basic auth only; Identity/Keycloak added in a later phase
8. **RDBMS-only** — No Elasticsearch; Aurora PostgreSQL handles all secondary storage (first DR reference to prove this)
9. **Odd/even broker distribution** — Even brokers in region 0, odd in region 1 (matching Camunda's Helm chart convention)
10. **Manual failover** — Shell script procedures for failover/failback (not automated)

## Architecture Sketch

```
Region 0 (e.g., eu-west-2)              Region 1 (e.g., eu-west-3)
+----------------------------------+     +----------------------------------+
| VPC 10.192.0.0/16               |     | VPC 10.202.0.0/16               |
|                                  |     |                                  |
| [ALB] HTTP/REST                  |     | [ALB] HTTP/REST                  |
| [NLB] gRPC :26500               |     | [NLB] gRPC :26500               |
| [NLB-internal] Raft :26502      |     | [NLB-internal] Raft :26502      |
|                                  |     |                                  |
| ECS Cluster                      |     | ECS Cluster                      |
|   4x Orchestration               |     |   4x Orchestration               |
|   (brokers 0, 2, 4, 6)          |     |   (brokers 1, 3, 5, 7)          |
|   1x Connectors                  |     |   1x Connectors                  |
|                                  |     |                                  |
| Cloud Map: r0-oc.service.local   |     | Cloud Map: r1-oc.service.local   |
| Route 53 Resolver Endpoint       |     | Route 53 Resolver Endpoint       |
|   (forwards r1-oc.* queries)     |     |   (forwards r0-oc.* queries)     |
|                                  |     |                                  |
| EFS (independent)                |     | EFS (independent)                |
| S3 (node ID: even IDs)          |     | S3 (node ID: odd IDs)           |
|                                  |     |                                  |
| Aurora Writer + Replicas         |     | Aurora Read Replicas             |
| (Global DB primary)             |     | (Global DB secondary)            |
+----------------+-----------------+     +----------------+-----------------+
                 |                                        |
                 +--------[Transit Gateway]---------------+
                    Cross-region Zeebe Raft (26502)
                    Route 53 Resolver forwarding
```

### Aurora Global Database Topology

```
Aurora Global Database
+-- Primary Cluster (Region 0)
|   +-- Writer instance (db.r6g.large)
|   +-- Reader instance(s)
+-- Secondary Cluster (Region 1)
    +-- Reader instance(s)
    +-- (Promoted to writer on failover)

JDBC Endpoints (via AWS JDBC Wrapper):
- Writer:  jdbc:aws-wrapper:postgresql://<global-writer-endpoint>:5432/camunda?wrapperPlugins=iam
- Reader:  jdbc:aws-wrapper:postgresql://<global-reader-endpoint>:5432/camunda?wrapperPlugins=iam
```

### Failover Flow (Manual)

```
1. Detect region 0 failure (monitoring/alerts)
2. Run: aurora-global-db-failover.sh
   - Promotes region 1 Aurora cluster to writer
   - AWS JDBC Wrapper auto-reconnects to new writer endpoint
3. Run: ecs-traffic-failover.sh
   - Update Route 53 records to point to region 1 ALB/NLB
   - Scale region 1 ECS services if needed
4. Zeebe Raft consensus recovers automatically
   - Surviving brokers (1, 3, 5, 7) maintain quorum for partitions
   - Partitions with majority in region 0 enter degraded state
5. Run: verify-failover.sh
   - Check Zeebe cluster health
   - Verify Aurora writer endpoint
   - Test end-to-end workflow execution
```

## Comparison: ECS DR (RDBMS) vs. EKS DR (Elasticsearch)

| Aspect | ECS Dual-Region (RDBMS) | EKS Dual-Region (ES) |
|---|---|---|
| Secondary storage | Aurora Global Database | Dual Elasticsearch clusters |
| Replication | Infrastructure-layer (<1s) | Application-layer (dual exporters) |
| Cross-region network | Transit Gateway | VPC Peering |
| Service discovery | Route 53 Resolver + Cloud Map | CoreDNS chaining |
| Broker identity | S3 node ID provider (odd/even) | K8s StatefulSet ordinals |
| Broker distribution | Even IDs region 0, odd IDs region 1 | Even IDs region 0, odd IDs region 1 |
| Data volume | EFS (per region) | EBS PVCs (per region) |
| Identity | Disabled (phased) | Disabled |
| Optimize | Not available (RDBMS mode) | Available (ES mode) |
| Failover | Manual scripts | Manual scripts |
| Complexity | Lower (no ES ops) | Higher (ECK + ES password sync) |

## Resolved Questions

1. **Broker distribution pattern**: Even-numbered brokers (0,2,4,6) in region 0, odd (1,3,5,7) in region 1. Replication factor 4. This matches the Camunda Helm chart convention and ensures balanced partition distribution via round-robin.

2. **Aurora Global Database write latency**: Accepted. Cross-region write latency (~50-100ms) for region 1 brokers is acceptable for a reference architecture.

3. **Cross-region service discovery**: Route 53 Resolver forwarding rules + Cloud Map namespaces per region. Each region resolves the other's Cloud Map namespace via Transit Gateway.

4. **Zeebe initial contact points**: Internal NLBs per region expose port 26502. Brokers use NLB DNS names for cross-region Raft communication. Local brokers use Cloud Map endpoints.

5. **Failover procedure**: Manual shell scripts. Steps: Aurora failover, DNS/traffic switch, Zeebe quorum recovery verification.

6. **RDBMS in dual-region**: Camunda docs say "not supported" but this is untested, not technically blocked. This reference architecture will be the first to prove it works with Aurora Global Database.

## Open Questions

1. **S3 Node ID Provider odd/even assignment**: The EKS Helm chart handles broker ID distribution via StatefulSet ordinals. The ECS S3 node ID provider needs to be configured to assign even IDs (0,2,4,6) in region 0 and odd IDs (1,3,5,7) in region 1. **Investigation needed**: does the provider support ID range constraints, or do we need a custom allocation mechanism?

2. **ECS task count per region**: With 4 brokers per region (up from 3 in single-region), validate that ECS Fargate handles 4 tasks with stable Service Connect endpoints. The `desired_count` and Service Connect port mappings may need adjustment.

## References

- Current ECS single-region: `aws/containers/ecs-single-region-fargate/`
- EKS dual-region pattern: `aws/kubernetes/eks-dual-region/`
- Aurora module: `aws/modules/aurora/`
- ECS modules: `aws/modules/ecs/fargate/`
- RDBMS values template: `generic/kubernetes/operator-based/postgresql/camunda-rdbms-values.yml`
- Camunda dual-region docs: https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/
- Camunda dual-region Zeebe config: https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/#zeebe-cluster-configuration
