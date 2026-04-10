# ECS dual-region (Fargate) – Camunda 8 reference architecture

This folder describes the IaC of Camunda on AWS ECS Fargate in a dual-region active-active setup using Aurora Global Database (RDBMS secondary storage).

> [!WARNING]
> This reference architecture is experimental. RDBMS-based dual-region for Camunda 8 is uncharted territory — expect rough edges. It is intended for learning and validation, not production use.

## Architecture overview

- **Two AWS regions** (default: `eu-west-2` and `eu-west-3`) connected via Transit Gateway
- **8 Zeebe brokers** — 4 per region with asymmetric initial contact points (Service Connect locally, NLB cross-region)
- **Aurora Global Database** — single writer endpoint with [AWS JDBC Wrapper](https://github.com/aws/aws-advanced-jdbc-wrapper) `failover` plugin for automatic reconnection
- **Route 53 Resolver** — forwards Cloud Map DNS queries cross-region for service discovery
- **RDBMS secondary storage** — uses PostgreSQL (Aurora) instead of Elasticsearch/OpenSearch

Cluster configuration: `cluster_size=8`, `replication_factor=4`, `partition_count=8`.

## Prerequisites

- AWS account with permissions for: ECS, Aurora, Transit Gateway, Route 53, S3, EFS, KMS, IAM, Secrets Manager, CloudWatch
- Two AWS regions with Transit Gateway peering established
- S3 bucket for Terraform state
- Camunda Docker image version 8.8+ (RDBMS secondary storage support)

## Quick start

```bash
# 1. Deploy infrastructure
cd terraform/clusters
terraform init && terraform apply

# 2. Export environment variables from terraform outputs
source ../../procedure/export_environment_prerequisites.sh

# 3. Verify cross-region DNS resolution
../../procedure/test_cross_region_dns.sh

# 4. Verify dual-region health
../../procedure/verify_dual_region.sh
```

## Failover / Failback

```bash
# Planned failover (switchover) to region 1
./procedure/failover.sh

# Unplanned failover (detach + promote) to region 1
./procedure/failover.sh --unplanned

# Failback to region 0
./procedure/failback.sh

# Failback and switch Aurora writer back to region 0
./procedure/failback.sh --switch-writer
```

## Known limitations

- **No Identity / Keycloak** — authentication is not included in this reference
- **No Optimize** — RDBMS secondary storage does not yet support Optimize
- **No WebModeler / Console** — not included
- **Node ID assignment** — even/odd broker ID assignment per region is pending (Spike 0.1)
- **Manual failover only** — no automated health-check-driven failover

## Related references

- [ECS single-region reference](../ecs-single-region-fargate/)
- [EKS dual-region reference](../../kubernetes/eks-dual-region/)
- [Camunda dual-region docs](https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/)
- [Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
