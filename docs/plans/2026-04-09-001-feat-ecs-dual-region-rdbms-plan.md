---
title: "feat: ECS Dual-Region Active-Active with Aurora Global Database (RDBMS)"
type: feat
status: active
date: 2026-04-09
origin: docs/brainstorms/2026-04-08-ecs-dual-region-rdbms-brainstorm.md
---

# feat: ECS Dual-Region Active-Active with Aurora Global Database (RDBMS)

## Overview

Build a dual-region active-active deployment of Camunda 8 on AWS ECS Fargate using Aurora Global Database (PostgreSQL) as the RDBMS secondary storage backend. This extends the existing `aws/containers/ecs-single-region-fargate/` reference architecture to span two AWS regions connected via Transit Gateway.

This will be the **first reference architecture to prove RDBMS secondary storage in a dual-region setup** — the current Camunda docs note it as unsupported, but that reflects a testing gap rather than a technical limitation (see brainstorm: `docs/brainstorms/2026-04-08-ecs-dual-region-rdbms-brainstorm.md`).

## Problem Statement / Motivation

The existing dual-region pattern (`aws/kubernetes/eks-dual-region/`) requires Elasticsearch with dual exporters — operationally complex and costly. The ECS single-region already uses Aurora PostgreSQL with RDBMS secondary storage, eliminating Elasticsearch entirely. Extending this to dual-region with Aurora Global Database provides:

- **Infrastructure-layer replication** (<1s lag) vs. application-layer dual ES exporters
- **Simpler operations** — no ECK, no cross-region ES password sync, no dual exporter configuration
- **Cost-effective** — Aurora Global Database vs. two Elasticsearch clusters
- **AWS-native** — Transit Gateway, Route 53 Resolver, Cloud Map (no CoreDNS hacks)

## Proposed Solution

### Architecture

```
Region 0 (eu-west-2)                    Region 1 (eu-west-3)
+----------------------------------+     +----------------------------------+
| VPC 10.192.0.0/16               |     | VPC 10.202.0.0/16               |
|                                  |     |                                  |
| [ALB] HTTP/REST :80              |     | [ALB] HTTP/REST :80              |
| [NLB-ext] gRPC :26500           |     | [NLB-ext] gRPC :26500           |
| [NLB-int] Raft :26502           |     | [NLB-int] Raft :26502           |
|                                  |     |                                  |
| ECS Cluster                      |     | ECS Cluster                      |
|   4x Orchestration               |     |   4x Orchestration               |
|   (brokers 0, 2, 4, 6)          |     |   (brokers 1, 3, 5, 7)          |
|   1x Connectors                  |     |   1x Connectors                  |
|                                  |     |                                  |
| Cloud Map: r0-oc.service.local   |     | Cloud Map: r1-oc.service.local   |
| R53 Resolver Inbound Endpoint    |     | R53 Resolver Inbound Endpoint    |
| R53 Resolver Fwd Rule → r1-oc   |     | R53 Resolver Fwd Rule → r0-oc   |
|                                  |     |                                  |
| EFS (independent)                |     | EFS (independent)                |
| S3 (node ID: even IDs)          |     | S3 (node ID: odd IDs)           |
| S3 (backup, CRR to region 1)    |     | S3 (backup, CRR replica)        |
|                                  |     |                                  |
| Aurora Writer + Replicas         |     | Aurora Read Replicas             |
| (Global DB primary)             |     | (Global DB secondary)            |
+----------------+-----------------+     +----------------+-----------------+
                 |                                        |
                 +--------[Transit Gateway]---------------+
                    Cross-region Raft (26502)
                    Route 53 Resolver forwarding
                    Aurora replication (<1s)
```

### Key Design Decisions (from brainstorm)

1. **Active-active** — 8 brokers, replication factor 4, even/odd distribution per region
2. **Aurora Global Database** — single writer in region 0, cross-region write latency ~50-100ms accepted
3. **Transit Gateway** — scalable cross-region networking (not VPC peering)
4. **Route 53 Resolver + Cloud Map** — AWS-native cross-region service discovery
5. **Internal NLB per region** — cross-region Raft port 26502
6. **EFS per region (independent)** — rebuilt via Raft on failover
7. **No Identity (MVP)** — basic auth only, phased
8. **RDBMS-only** — no Elasticsearch
9. **Manual failover** — shell script procedures

### Broker Distribution

Per [Camunda docs](https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/#zeebe-cluster-configuration):
- Even-numbered brokers (0, 2, 4, 6) → Region 0
- Odd-numbered brokers (1, 3, 5, 7) → Region 1
- 8 partitions, replication factor 4
- `CAMUNDA_CLUSTER_SIZE=8` in both regions (total cluster, not per-region)
- `CAMUNDA_CLUSTER_REPLICATIONFACTOR=4`

### Initial Contact Points (Asymmetric per Region)

Service Connect aliases only resolve locally (sidecar-intercepted). Cross-region discovery uses internal NLBs:

- **Region 0**: `r0-oc-sc:26502,<r1-internal-nlb-dns>:26502`
- **Region 1**: `r1-oc-sc:26502,<r0-internal-nlb-dns>:26502`

### JDBC Configuration

Both regions point to the Aurora Global Database primary cluster writer endpoint via the AWS JDBC Wrapper with IAM auth + failover plugin:

```
jdbc:aws-wrapper:postgresql://<primary-cluster-endpoint>:5432/camunda?wrapperPlugins=iam,failover
```

After Aurora Global DB failover, the wrapper detects topology change and reconnects to the new writer.

## Technical Considerations

### Architecture Impacts

- **New Terraform module needed**: `aws/modules/aurora-global/` wrapping `aws_rds_global_cluster` + regional clusters
- **Orchestration-cluster module changes**: support for `CAMUNDA_CLUSTER_SIZE` separate from `task_desired_count`, internal NLB for Raft, asymmetric initial contact points
- **New infrastructure patterns**: Transit Gateway, Route 53 Resolver (no existing patterns in repo)
- **Single Terraform state** with provider aliases (matching EKS dual-region pattern)

### Performance Implications

- Cross-region Raft consensus adds ~50-100ms per round-trip
- Aurora writes from region 1 brokers add ~50-100ms (writer in region 0)
- Health check grace period may need increase (900s → 1200s) for cross-region Raft formation

### Security Considerations

- Security groups scoped to specific ports between VPC CIDRs:
  - 26502 (Raft), 5432 (Aurora), 53 (DNS resolver)
- Aurora IAM auth preserved (no passwords at runtime)
- KMS keys are region-specific (separate keys per region)
- Transit Gateway does not cross account boundaries (single account)

## System-Wide Impact

### Interaction Graph

- ECS Service → Service Connect (local) → Cloud Map → Route 53 Resolver (cross-region) → Remote Cloud Map
- ECS Task → Internal NLB (cross-region) → Transit Gateway → Remote ECS Task (Raft 26502)
- ECS Task → Aurora Global DB Writer (may cross region) → Aurora Replication → Secondary Cluster
- Failover script → Aurora API (failover) → JDBC Wrapper (auto-reconnect) → New writer

### Error Propagation

- **Aurora writer failure**: JDBC Wrapper retries; if region-level failure, manual failover script triggers Global DB promotion
- **Transit Gateway disruption**: Raft consensus degrades to per-region quorum; partitions with cross-region leaders lose quorum
- **Service Connect failure**: Local brokers cannot discover each other; health checks fail; ECS restarts tasks
- **S3 node ID failure**: Brokers cannot acquire identity on startup; ECS tasks remain in pending/unhealthy state

### State Lifecycle Risks

- **Split-brain on Aurora Global DB failover**: if both regions believe they are the writer, data corruption possible. Mitigation: Aurora Global DB handles this at infrastructure level with fencing.
- **Stale EFS data on failback**: returning brokers have outdated EFS volumes. Mitigation: Raft snapshot transfer catches up; optionally wipe EFS before restart.
- **Orphaned S3 node ID leases**: if a broker crashes, its lease persists for `PT15S`. If 4 brokers crash simultaneously (region failure), 4 leases expire within 15 seconds.

### API Surface Parity

- External: ALB (HTTP/REST port 80) + NLB (gRPC port 26500) — identical per region
- Internal: Service Connect (local) + Internal NLB (cross-region Raft 26502)
- DB: Aurora Global DB writer endpoint (both regions use same)
- No Helm values (ECS-only, no Kubernetes)

### Integration Test Scenarios

1. **Deploy both regions → verify 8-broker Raft quorum → execute workflow → verify RDBMS writes**
2. **Failover region 0 → verify region 1 takes over → execute workflow → verify Aurora writer promotion**
3. **Failback region 0 → verify brokers rejoin → verify balanced partition distribution**
4. **Cross-region latency test → measure gRPC response time from each region**
5. **Transit Gateway disruption → verify graceful degradation → restore → verify recovery**

## Acceptance Criteria

### Functional Requirements

- [ ] 8 Zeebe brokers form Raft consensus across 2 regions (4 per region, even/odd split)
- [ ] Aurora Global Database replicates RDBMS secondary storage data cross-region (<1s lag)
- [ ] Workflows execute successfully from either region's gateway
- [ ] Failover procedure: region 0 failure → region 1 fully operational within documented RTO
- [ ] Failback procedure: region 0 recovery → balanced active-active operation restored
- [ ] Cross-region service discovery works via Route 53 Resolver + Cloud Map
- [ ] Internal NLBs route Raft traffic cross-region over Transit Gateway
- [ ] DB seed task creates `camunda` role with IAM auth on Aurora Global DB primary

### Non-Functional Requirements

- [ ] Terraform applies cleanly from scratch (`terraform apply`)
- [ ] Terraform destroys cleanly (`terraform destroy`)
- [ ] Golden file tests pass for the new reference architecture
- [ ] CI workflow follows repo naming conventions
- [ ] Procedure scripts use `set -euo pipefail` and are idempotent
- [ ] All actions pinned to commit SHAs in GitHub workflows

### Quality Gates

- [ ] All acceptance criteria verified via integration test
- [ ] Failover + failback tested end-to-end
- [ ] Documentation (README) links to Camunda dual-region docs
- [ ] Code reviewed for security (IAM, SGs scoped to specific ports)

## Success Metrics

- 8 brokers form quorum across 2 regions
- Workflow execution succeeds from both regions
- Aurora Global DB failover completes; services reconnect automatically
- Failback restores balanced operation
- RDBMS secondary storage works in dual-region (proving the docs wrong)

## Implementation Phases

### Phase 0: Investigation Spikes (Pre-requisites)

**Goal**: Resolve critical unknowns before committing to the architecture.

#### Spike 0.1: S3 Node ID Provider — Odd/Even ID Assignment

**Risk**: CRITICAL — blocks entire implementation

Investigate whether the Camunda S3 node ID provider supports constraining which broker IDs a task can acquire. Options to investigate:

1. Check for `CAMUNDA_CLUSTER_NODEIDPROVIDER_S3_ALLOWEDIDS` or similar env var
2. Check Camunda source code for the S3 node ID provider implementation
3. Test with a local setup: can separate S3 buckets with pre-seeded marker files force specific IDs?
4. Fallback: custom entrypoint script that claims specific IDs before starting Camunda

**Files to examine**:
- `aws/modules/ecs/fargate/orchestration-cluster/ecs.tf:26-42` — current S3 node ID config
- Camunda source for `io.camunda.zeebe.broker.clustering.topology.s3` (or similar package)

**Deliverable**: Document the mechanism to assign even IDs in region 0 and odd IDs in region 1, or identify the workaround.

#### Spike 0.2: Aurora Global Database JDBC Wrapper Failover

**Risk**: HIGH — affects write path correctness

Validate the AWS JDBC Wrapper behavior with Aurora Global Database:

1. Create minimal Aurora Global DB (primary + secondary)
2. Configure JDBC Wrapper with `wrapperPlugins=iam,failover`
3. Trigger Global DB failover
4. Verify wrapper auto-reconnects to new writer endpoint
5. Measure reconnection time

**Deliverable**: Working JDBC URL configuration + documented failover behavior.

#### Spike 0.3: ECS Service Connect + Route 53 Resolver Cross-Region

**Risk**: HIGH — affects broker discovery

Validate that Route 53 Resolver forwarding rules can resolve Cloud Map namespaces across Transit Gateway:

1. Create 2 VPCs + Transit Gateway + Route 53 Resolver endpoints
2. Create Cloud Map namespace in each VPC
3. Register a test service in each namespace
4. Verify cross-region DNS resolution via Resolver forwarding rules

**Deliverable**: Working Terraform for Route 53 Resolver + Cloud Map cross-region resolution.

### Phase 1: Foundation Infrastructure

**Goal**: Create the base networking, Transit Gateway, and Aurora Global Database.

**Directory structure**:
```
aws/containers/ecs-dual-region-fargate/
├── terraform/
│   └── clusters/          # Single state, dual-provider (like EKS DR)
│       ├── config.tf      # Backend + provider aliases (aws, aws.accepter)
│       ├── variables.tf   # Region configs (owner/accepter pattern)
│       ├── locals.tf      # Computed values
│       ├── vpc.tf         # Two VPCs
│       ├── transit-gateway.tf  # TGW + VPC attachments + routes
│       ├── dns.tf         # Route 53 Resolver endpoints + forwarding rules
│       ├── aurora-global.tf    # Aurora Global DB (primary + secondary)
│       ├── postgres_seed.tf    # DB bootstrap (region 0 only)
│       ├── kms.tf         # Per-region KMS keys
│       ├── secrets.tf     # Secrets Manager per region
│       ├── iam.tf         # IAM roles per region
│       ├── security.tf    # Security groups per region
│       ├── ecs.tf         # ECS clusters per region
│       ├── camunda.tf     # Orchestration + Connectors modules per region
│       ├── lb.tf          # ALBs + NLBs (external + internal) per region
│       ├── s3.tf          # Backup buckets + node ID buckets per region
│       ├── outputs.tf
│       └── test/
│           ├── fixtures/ci/
│           │   └── fixture_camunda_override.tf
│           └── golden/
│               ├── golden.tfvars
│               └── tfplan-golden.json
├── procedure/
│   ├── export_environment_prerequisites.sh
│   ├── failover.sh
│   ├── failback.sh
│   ├── verify_dual_region.sh
│   └── test_cross_region_dns.sh
└── test/
    └── (integration tests)
```

#### Task 1.1: Create Reference Architecture Skeleton

- [ ] Create `aws/containers/ecs-dual-region-fargate/` directory structure
- [ ] Create `terraform/clusters/config.tf` with S3 backend + dual provider aliases (`aws` for region 0, `aws.accepter` for region 1)
- [ ] Create `terraform/clusters/variables.tf` with owner/accepter region configuration (matching EKS DR pattern at `aws/kubernetes/eks-dual-region/terraform/clusters/variables.tf`)
- [ ] Create `terraform/clusters/locals.tf` with computed values (prefix, region names, CIDRs)

**Reference**: `aws/kubernetes/eks-dual-region/terraform/clusters/config.tf:20-37`

#### Task 1.2: VPC + Transit Gateway

- [ ] Create `vpc.tf` — two VPCs (10.192.0.0/16, 10.202.0.0/16) using `terraform-aws-modules/vpc/aws`, 3 AZs each, NAT gateways, DNS support
- [ ] Create `transit-gateway.tf` — TGW resource, VPC attachments in both regions, route table entries for cross-VPC CIDRs in both public and private route tables
- [ ] Security group ingress rules allowing traffic from remote VPC CIDR on ports 26502 (Raft), 5432 (Aurora), 53 (DNS)

**Reference**: `aws/containers/ecs-single-region-fargate/terraform/cluster/vpc.tf`, Transit Gateway design spec at `docs/superpowers/specs/2026-04-08-transit-gateway-dual-region-design.md`

#### Task 1.3: Route 53 Resolver

- [ ] Create `dns.tf` — Route 53 Resolver inbound endpoints in each VPC (for receiving forwarded queries)
- [ ] Route 53 Resolver outbound endpoints in each VPC (for sending queries to remote region)
- [ ] Forwarding rules: region 0 forwards `r1-oc.service.local` → region 1 inbound endpoint; region 1 forwards `r0-oc.service.local` → region 0 inbound endpoint
- [ ] Security groups for Resolver endpoints (UDP/TCP 53)

**Note**: This is a net-new pattern — no existing implementation in the repo.

#### Task 1.4: Aurora Global Database Module

- [ ] Create `aws/modules/aurora-global/` module:
  - `main.tf` — `aws_rds_global_cluster`, primary `aws_rds_cluster` (region 0), secondary `aws_rds_cluster` (region 1, no master credentials)
  - `variables.tf` — engine version, instance class, global cluster identifier, primary/secondary subnet group IDs, security group IDs, KMS key ARNs per region
  - `outputs.tf` — global cluster ID, primary writer endpoint, secondary reader endpoint, cluster identifiers
  - `versions.tf` — provider constraints
- [ ] Wire into `aurora-global.tf` in the clusters root
- [ ] DB seed task in `postgres_seed.tf` (region 0 only, connects to primary writer endpoint)

**Reference**: `aws/modules/aurora/main.tf` (single-region pattern)

### Phase 2: ECS Cluster + Orchestration Module Updates

**Goal**: Deploy 8 Zeebe brokers across 2 regions with correct Raft configuration.

#### Task 2.1: Orchestration-Cluster Module Enhancements

Update `aws/modules/ecs/fargate/orchestration-cluster/` to support dual-region:

- [ ] Add variable `cluster_size` (total brokers, default = `task_desired_count`) — used for `CAMUNDA_CLUSTER_SIZE` env var
- [ ] Add variable `replication_factor` (default = 1) — used for `CAMUNDA_CLUSTER_REPLICATIONFACTOR`
- [ ] Add variable `initial_contact_points` (string) — allows overriding `CAMUNDA_CLUSTER_INITIALCONTACTPOINTS`
- [ ] Add variable `internal_nlb_arn` (optional) — for internal NLB target group registration on port 26502
- [ ] Add internal NLB target group + listener in `lb.tf` (conditional on `internal_nlb_arn` being set)
- [ ] Add variable `node_id_allowed_ids` (optional string) — for S3 node ID provider ID constraints (pending Spike 0.1)
- [ ] Add variable `region_id` (optional number) — for `global.multiregion.regionId` equivalent

**Files to modify**:
- `aws/modules/ecs/fargate/orchestration-cluster/variables.tf`
- `aws/modules/ecs/fargate/orchestration-cluster/ecs.tf`
- `aws/modules/ecs/fargate/orchestration-cluster/lb.tf`
- `aws/modules/ecs/fargate/orchestration-cluster/output.tf`

#### Task 2.2: ECS Clusters + Services

- [ ] Create `ecs.tf` — two ECS clusters (one per region)
- [ ] Create `camunda.tf` — invoke `orchestration-cluster` module twice (region 0 and region 1) with:
  - `task_desired_count = 4` (per region)
  - `cluster_size = 8` (total)
  - `replication_factor = 4`
  - Region-specific `initial_contact_points` (asymmetric: local SC + remote NLB)
  - Region-specific `environment_variables` for RDBMS config (Aurora Global DB writer endpoint)
  - Region-specific `node_id_allowed_ids` (even for region 0, odd for region 1)
- [ ] Invoke `connectors` module twice (one per region), each connecting to local orchestration Service Connect
- [ ] Create `lb.tf` — per region: ALB (port 80), external NLB (port 26500), internal NLB (port 26502)

**Reference**: `aws/containers/ecs-single-region-fargate/terraform/cluster/camunda.tf`

#### Task 2.3: Security Groups

- [ ] Create `security.tf` with per-region security groups:
  - Camunda ports (8080, 9600, 26500, 26502) — local VPC CIDR
  - Cross-region Raft (26502) — remote VPC CIDR
  - Aurora (5432) — both VPC CIDRs
  - EFS (2049) — local VPC CIDR
  - DNS Resolver (53) — both VPC CIDRs
  - ALB/NLB ingress from `limit_access_to_cidrs`

**Reference**: `aws/containers/ecs-single-region-fargate/terraform/cluster/security.tf`

#### Task 2.4: Supporting Infrastructure

- [ ] `kms.tf` — per-region KMS keys (S3, Secrets Manager, Aurora, EFS)
- [ ] `secrets.tf` — per-region Secrets Manager secrets (db-admin-password, oc-admin-password, connectors-auth-password)
- [ ] `s3.tf` — per-region backup buckets (with S3 CRR from region 0 → region 1), per-region node ID buckets
- [ ] `iam.tf` — per-region IAM roles (task execution, task role with RDS IAM connect, S3 access, EFS access)

### Phase 3: Procedure Scripts

**Goal**: Manual failover/failback procedures + verification scripts.

#### Task 3.1: Environment Prerequisites Script

- [ ] Create `procedure/export_environment_prerequisites.sh`:
  - Export region-specific vars: `REGION_0`, `REGION_1`, `CLUSTER_0`, `CLUSTER_1`, `VPC_0`, `VPC_1`
  - Export Aurora Global DB identifiers
  - Export NLB DNS names, ALB DNS names
  - Export S3 bucket names

**Reference**: `aws/kubernetes/eks-dual-region/procedure/export_environment_prerequisites.sh`

#### Task 3.2: Cross-Region DNS Verification

- [ ] Create `procedure/test_cross_region_dns.sh`:
  - Test Route 53 Resolver forwarding from region 0 → region 1 Cloud Map namespace
  - Test Route 53 Resolver forwarding from region 1 → region 0 Cloud Map namespace
  - Verify internal NLB DNS resolution from both regions

**Reference**: `aws/kubernetes/eks-dual-region/procedure/test_dns_chaining.sh`

#### Task 3.3: Failover Script

- [ ] Create `procedure/failover.sh`:
  1. Verify current state (Aurora writer in region 0, both regions healthy)
  2. Aurora Global DB failover: `aws rds failover-global-cluster` (planned) or detach+promote (unplanned)
  3. Wait for Aurora failover completion
  4. Update Route 53 records to direct client traffic to region 1 ALB/NLB
  5. Verify Zeebe quorum in region 1 (4 surviving brokers)
  6. Verify workflow execution from region 1
  7. Report status

#### Task 3.4: Failback Script

- [ ] Create `procedure/failback.sh`:
  1. Verify current state (Aurora writer in region 1, region 0 recovered)
  2. If Global DB relationship broken: re-add region 0 as secondary cluster
  3. Wait for Aurora data sync
  4. Scale ECS services in region 0 (tasks acquire even broker IDs)
  5. Wait for Zeebe brokers to rejoin Raft cluster
  6. Aurora failback: promote region 0 back to writer
  7. Redistribute Route 53 traffic to both regions
  8. Verify balanced 8-broker operation

#### Task 3.5: Verification Script

- [ ] Create `procedure/verify_dual_region.sh`:
  - Check Zeebe cluster topology (8 brokers, 8 partitions)
  - Check partition distribution (balanced across regions)
  - Check Aurora Global DB replication status
  - Check Aurora writer endpoint location
  - Execute test workflow from each region
  - Report overall health

### Phase 4: CI/CD + Testing

**Goal**: GitHub workflows, golden file tests, integration tests.

#### Task 4.1: GitHub Workflow

- [ ] Create `.github/workflows/aws_ecs_dual_region_fargate_tests.yml`:
  - Name: `Tests - Integration - AWS Containers ECS Dual Region Fargate`
  - Triage job with `internal-triage-skip` action
  - Skip label: `skip_aws_ecs_dual_region_fargate_tests`
  - Jobs: triage → clusters-info → prepare-clusters → integration-tests → cleanup-clusters → report
- [ ] Create `.github/workflows/aws_ecs_dual_region_fargate_daily_cleanup.yml`
- [ ] Create `.github/workflows/aws_ecs_dual_region_fargate_golden.yml`
- [ ] Create `.github/actions/aws-containers-ecs-dual-region-fargate-create/action.yml` composite action
- [ ] Create `.github/workflows-config/aws-containers-ecs-dual-region-fargate/test_matrix.yml`
- [ ] Add schedule entry to `.github/workflows-config/workflow-scheduler.yml`

**Reference**: `.github/workflows/aws_ecs_single_region_fargate_tests.yml`

#### Task 4.2: Golden File Tests

- [ ] Create `terraform/clusters/test/golden/golden.tfvars` with minimal values
- [ ] Generate initial golden file: `just regenerate-golden-file`
- [ ] Create `terraform/clusters/test/fixtures/ci/fixture_camunda_override.tf` with `force_destroy = true`

#### Task 4.3: Integration Tests

- [ ] Create integration test suite (Go or shell-based, matching ECS single-region pattern):
  1. Deploy infrastructure (`terraform apply`)
  2. Wait for ECS services healthy in both regions
  3. Verify 8-broker Raft quorum
  4. Execute workflow from region 0 gateway
  5. Execute workflow from region 1 gateway
  6. Run failover procedure
  7. Verify region 1 standalone operation
  8. Run failback procedure
  9. Verify balanced dual-region operation
  10. Cleanup (`terraform destroy`)

### Phase 5: Documentation

#### Task 5.1: README

- [ ] Create `aws/containers/ecs-dual-region-fargate/README.md`:
  - Architecture overview with diagram
  - Prerequisites (AWS accounts, Transit Gateway)
  - Quick start (terraform apply + procedure scripts)
  - Failover/failback guide
  - Known limitations (no Identity, no Optimize, RDBMS dual-region is uncharted)
  - Link to Camunda dual-region docs

## Alternative Approaches Considered

| Approach | Why Rejected |
|---|---|
| **Active-Passive** | Simpler but doesn't demonstrate Camunda's dual-region active-active capability (see brainstorm) |
| **VPC Peering** (instead of TGW) | Non-transitive, doesn't scale, less production-realistic (see brainstorm) |
| **Elasticsearch secondary storage** | Defeats the purpose — ECS single-region already proves RDBMS works; extending ES to dual-region adds complexity (see brainstorm) |
| **Extending existing Aurora module** | Too much conditional logic; new `aurora-global` module is cleaner and doesn't break existing consumers |
| **Separate Terraform states per region** | More isolated but adds orchestration complexity; single state with provider aliases is consistent with EKS dual-region pattern |

## Dependencies & Prerequisites

- **Phase 0 spikes must complete before Phase 1** — especially Spike 0.1 (S3 node ID provider)
- Camunda Docker image version supporting RDBMS secondary storage (8.8+)
- AWS account with permissions for: ECS, Aurora, Transit Gateway, Route 53, S3, EFS, KMS, IAM, Secrets Manager, CloudWatch
- Two AWS regions (default: eu-west-2, eu-west-3)
- S3 bucket for Terraform state

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| S3 node ID provider doesn't support ID constraints | Medium | Critical | Spike 0.1; fallback: custom init container or separate buckets with pre-seeded IDs |
| RDBMS dual-region has undiscovered bugs | Medium | High | This is explicitly a proving ground; document issues found, report to Camunda |
| Aurora Global DB failover breaks JDBC Wrapper auto-reconnect | Low | High | Spike 0.2 validates this; fallback: manual endpoint reconfiguration |
| Route 53 Resolver can't forward Cloud Map queries cross-region | Low | High | Spike 0.3 validates this; fallback: explicit NLB DNS names in initial contact points |
| Cross-region Raft latency causes timeouts | Low | Medium | Tune Raft timeouts; 50-100ms is well within Zeebe defaults |
| ECS Service Connect doesn't scale to 4 tasks per service reliably | Low | Medium | Test in Phase 2; fallback: increase desired_count or use individual task definitions |

## Future Considerations

- **Phase 2: Identity/Keycloak** — add cross-region Keycloak with shared Aurora backend
- **Automated failover** — Route 53 health checks + Lambda for Aurora + ECS auto-scaling
- **Optimize support** — when/if RDBMS secondary storage supports Optimize
- **EFS cross-region replication** — for faster failback (currently Raft rebuilds data)
- **Multi-account** — Transit Gateway with RAM sharing for landing zone patterns
- **WebModeler + Console** — additional Camunda components

## Sources & References

### Origin

- **Brainstorm document**: [docs/brainstorms/2026-04-08-ecs-dual-region-rdbms-brainstorm.md](docs/brainstorms/2026-04-08-ecs-dual-region-rdbms-brainstorm.md) — Key decisions carried forward: active-active model, Aurora Global DB, Transit Gateway, Route 53 Resolver, manual failover, RDBMS-only (first dual-region proof)

### Internal References

- ECS single-region reference: `aws/containers/ecs-single-region-fargate/`
- EKS dual-region reference: `aws/kubernetes/eks-dual-region/`
- Aurora module: `aws/modules/aurora/main.tf`
- ECS orchestration module: `aws/modules/ecs/fargate/orchestration-cluster/`
- ECS connectors module: `aws/modules/ecs/fargate/connectors/`
- Transit Gateway design spec: `docs/superpowers/specs/2026-04-08-transit-gateway-dual-region-design.md`
- Transit Gateway implementation plan: `docs/superpowers/plans/2026-04-08-transit-gateway-dual-region.md`
- RDBMS values template: `generic/kubernetes/operator-based/postgresql/camunda-rdbms-values.yml`

### External References

- Camunda dual-region docs: https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/
- Camunda Zeebe cluster configuration: https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/#zeebe-cluster-configuration
- AWS Aurora Global Database: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html
- AWS JDBC Wrapper: https://github.com/aws/aws-advanced-jdbc-wrapper
- AWS Transit Gateway: https://docs.aws.amazon.com/vpc/latest/tgw/
- AWS Route 53 Resolver: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html
