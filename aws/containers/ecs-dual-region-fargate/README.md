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

## Terraform backend

By default, all three states use `backend "s3"`. You must supply backend configuration during `terraform init`:

```bash
# S3 backend (production — recommended)
terraform init \
  -backend-config="bucket=my-tf-state-bucket" \
  -backend-config="key=ecs-dual-region/vpc/terraform.tfstate" \
  -backend-config="region=eu-west-2"
```

For **local-only testing** (no S3 bucket needed), change each `config.tf` to use a local backend:

```hcl
# In terraform/{vpc,infra,app}/config.tf, replace:
#   backend "s3" { encrypt = true }
# with:
  backend "local" {}
```

Then run `terraform init`. Cross-state references (`terraform_remote_state` in `infra/` and `app/`) already default to local file paths (`../vpc/terraform.tfstate` and `../infra/terraform.tfstate`).

## Terraform layout

Three independent states, deployed in order:

```
terraform/
├── vpc/    ← VPCs, cross-region peering or Transit Gateway, optional Route 53 Resolver.
│            Supports BYO-VPC: customers can supply existing VPCs/subnets via vars.
├── infra/  ← Aurora Global, ECS clusters, ALB/NLBs, KMS, S3, secrets, IAM.
│            Reads vpc outputs via terraform_remote_state.
└── app/    ← Camunda task definitions + ECS services.
             Reads infra outputs via terraform_remote_state.
```

## Deploy time and cost

Wall-clock for a greenfield deploy to first healthy `/v2/topology` returning 8 brokers:

| Phase | Wall clock | What's slow |
|-------|-----------|-------------|
| `vpc/ apply` | ~3-5 min | VPCs + cross-region peering or Transit Gateway |
| `infra/ apply` | ~15-20 min | Aurora Global Database (primary first, then secondary attaches) |
| `app/ apply` | ~30s plan + ~15-20 min Raft | ECS service rollout waits for steady state; Raft quorum across regions takes 15-20 min the first time |
| **Total** | **~35-45 min** | |

`terraform destroy` is faster: ~15-20 min end-to-end, with Aurora teardown again the bottleneck.

Rough running cost for the default sizing (4 brokers per region, 1 connectors task per region, Aurora db.r6g.large × 2 instances per region, 1 NAT GW per region, 2 ALBs, 4 NLBs):

| Component | Approx. cost/day |
|-----------|------------------|
| Fargate orchestration cluster (4 vCPU/8 GB × 8 tasks) | ~$38 |
| Fargate connectors (2 vCPU/4 GB × 2 tasks) | ~$5 |
| Aurora Global (db.r6g.large × 4 instances) | ~$28 |
| 2 × ALB + 4 × NLB | ~$5 |
| 2 × NAT Gateway (data transfer extra) | ~$2 |
| EFS, S3, Secrets Manager, KMS | ~$1 |
| **Total** | **~$80/day** |

These are list-price ballparks for `us-east-1`; commit discounts, region, idle time, and data egress will shift them. Always run `terraform destroy` when you're done with a demo.

## Quick start

Use the guided workflow (recommended): run `/ecs-dual-region/1-configure` … `/6-cleanup` in your Claude Code session.

Or manually:

```bash
# 1. Deploy VPC layer (~5 min greenfield, < 1 min BYO-VPC)
cd terraform/vpc
terraform init && terraform apply

# 2. Deploy infra layer (~15-20 min — Aurora Global is the bottleneck)
cd ../infra
terraform init && terraform apply

# 3. Deploy Camunda app layer (~30s apply, ~20 min Raft quorum formation)
cd ../app
terraform init && terraform apply

# 4. Export environment variables from terraform outputs
source ../../procedure/export_environment_prerequisites.sh

# 5. Verify cross-region DNS resolution (if enable_cross_region_dns_resolver = true)
../../procedure/test_cross_region_dns.sh

# 6. Verify dual-region health
../../procedure/verify_dual_region.sh
```

### BYO-VPC

Customers with existing VPCs can skip greenfield VPC creation by setting `byo_vpc = true` in `terraform/vpc/terraform.tfvars` and supplying VPC IDs, CIDRs, subnet IDs, and route table IDs. See `terraform/vpc/README.md` for the full contract — validation enforces it at plan time.

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

## Accessing the deployment

### Retrieve credentials

Camunda 8.10 requires basic auth on the unified `/v2/*` REST API. Two users are seeded at first boot:

- `admin` — full access, used to log into the Web UI
- `connectors` — used by the connectors-bundle to call the orchestration cluster

Both passwords are auto-generated (32 random characters) and stored in AWS Secrets Manager. They are **not** `demo:demo` (this matches the single-region Terraform reference).

```bash
# The admin password is generated once at infra/ apply and shared by both regions.
cd terraform/infra
ADMIN_PASS=$(terraform output -raw admin_user_password)
echo "admin / $ADMIN_PASS"

# The connectors-bundle password is also kept in Secrets Manager; retrieve via AWS CLI:
SECRET_ARN=$(terraform output -raw connectors_password_secret_region_0_arn)
CONNECTORS_PASS=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text)
```

Or via the AWS Console: Secrets Manager → `<cluster_name>-r0-oc-admin-user-password-*`.

### Method A — direct via ALB

The ALB is reachable from any IP in `limit_access_to_cidrs` (see `terraform/infra/terraform.tfvars`). For an internet-facing demo this is the easiest path:

```bash
ALB_R0=$(terraform output -raw region_0_alb_endpoint)

# Topology (auth required on 8.10)
curl -s -u "admin:${ADMIN_PASS}" "http://${ALB_R0}/v2/topology" | jq '.brokers | length'
# Expected: 8 (4 brokers per region once Raft has settled)

# Open Operate / Tasklist in a browser
open "http://${ALB_R0}/operate"
```

If you locked `limit_access_to_cidrs` down to a single corporate CIDR, switch to Method B.

### Method B — Session Manager port-forward (no public IP)

Use this when the ALB is not reachable from your laptop (private deployment, locked-down CIDRs, customer audit requirement). It piggybacks on the ECS Exec channel — no bastion host needed.

Requirements:
- `task_enable_execute_command = true` on the orchestration cluster module (this reference architecture sets it to `true` by default — see `terraform/app/camunda.tf`).
- The task IAM role must allow `ssmmessages:Create*` / `OpenDataChannel` / `OpenControlChannel` (the `ecs_exec_policy` in the module already grants these).
- [AWS Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) installed locally:
  - macOS: `brew install --cask session-manager-plugin`
  - Linux: see the AWS docs link above

```bash
# 1. Pick a running orchestration-cluster task in region 0
CLUSTER=$(cd terraform/infra && terraform output -raw cluster_name)
TASK_ARN=$(aws ecs list-tasks \
  --cluster "${CLUSTER}-r0-cluster" \
  --service-name "${CLUSTER}-r0-oc-orchestration-cluster" \
  --query 'taskArns[0]' --output text)
TASK_ID=${TASK_ARN##*/}

# 2. Resolve the ECS-managed runtime ID (Session Manager target)
RUNTIME_ID=$(aws ecs describe-tasks \
  --cluster "${CLUSTER}-r0-cluster" \
  --tasks "$TASK_ID" \
  --query 'tasks[0].containers[?name==`orchestration-cluster`].runtimeId' --output text)

# 3. Start a port-forwarding session: localhost:8080 → container 8080
aws ssm start-session \
  --target "ecs:${CLUSTER}-r0-cluster_${TASK_ID}_${RUNTIME_ID}" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'

# 4. In another shell, open the UI
open http://localhost:8080
# Log in as admin / $ADMIN_PASS
```

### Endpoint reference

| Endpoint | Port | Protocol | Purpose |
|----------|------|----------|---------|
| ALB (region 0/1) | 80 | HTTP | Camunda REST API, Web UI (routes to container 8080) |
| ALB (region 0/1) | 9600 | HTTP | Management / metrics |
| NLB external (region 0/1) | 26500 | TCP | Zeebe gRPC (client access) |
| NLB internal (region 0/1) | 26502 | TCP | Zeebe Raft (cross-region, private) |

### Cleanup notes

`s3_force_destroy` is `true` by default so `terraform destroy` doesn't leave orphaned S3 backup buckets. **Flip it to `false` in `terraform/infra/terraform.tfvars` before running any real workload through this stack** — otherwise Terraform will happily delete backup data on `destroy`.

#### Teardown after a failover

If you ran `failover.sh` (planned or unplanned) before destroying, the Aurora Global cluster writer has moved to region 1. Terraform expects the original topology and `terraform destroy` may hang on Aurora resources. To work around this:

```bash
# 1. Remove both clusters from the Global cluster
aws rds remove-from-global-cluster \
  --global-cluster-identifier <global-id> \
  --db-cluster-identifier <region-0-cluster-arn>

# 2. Delete instances in both regions (skip-final-snapshot for dev)
aws rds delete-db-instance --db-instance-identifier <r0-instance> --skip-final-snapshot --region <region-0>
aws rds delete-db-instance --db-instance-identifier <r1-instance> --skip-final-snapshot --region <region-1>

# 3. Wait for instances to delete, then delete clusters
aws rds delete-db-cluster --db-cluster-identifier <r0-cluster> --skip-final-snapshot --region <region-0>
aws rds delete-db-cluster --db-cluster-identifier <r1-cluster> --skip-final-snapshot --region <region-1>

# 4. Delete the global cluster
aws rds delete-global-cluster --global-cluster-identifier <global-id>

# 5. Remove Aurora resources from Terraform state and proceed with destroy
terraform -chdir=terraform/infra state rm 'module.aurora_global[0].aws_rds_cluster_instance.primary[0]'
terraform -chdir=terraform/infra state rm 'module.aurora_global[0].aws_rds_cluster_instance.secondary[0]'
terraform -chdir=terraform/infra state rm 'module.aurora_global[0].aws_rds_cluster.primary'
terraform -chdir=terraform/infra state rm 'module.aurora_global[0].aws_rds_cluster.secondary'
terraform -chdir=terraform/infra state rm 'module.aurora_global[0].aws_rds_global_cluster.this'
terraform -chdir=terraform/infra destroy -auto-approve
```

## Known limitations

- **No Identity / Keycloak** — authentication is not included in this reference
- **No Optimize** — RDBMS secondary storage does not yet support Optimize
- **No WebModeler / Console** — not included
- **Node ID assignment** — even/odd broker ID assignment per region is pending (Spike 0.1)
- **Manual failover only** — no automated health-check-driven failover
- **ECS circuit breaker disabled for orchestration clusters** — the deployment circuit breaker is set to `false` on both orchestration cluster services. On a first deploy, Zeebe brokers fail ECS health checks transiently while Aurora IAM auth warms up and cross-region Raft quorum forms (~20 min). The ECS threshold (`ceil(0.5 × desiredCount)`, min 10) would fire before the cluster self-heals. With the breaker disabled, ECS keeps retrying until the `service_timeouts.create` deadline (30 min). Once the cluster is stable, re-enabling the breaker is safe for subsequent deploys.

## Related references

- [ECS single-region reference](../ecs-single-region-fargate/)
- [EKS dual-region reference](../../kubernetes/eks-dual-region/)
- [Camunda dual-region docs](https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/)
- [Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
