# ECS Dual-Region Fargate — Claude Commands Design

**Date:** 2026-04-16
**Status:** Approved
**Branch:** feat/ecs-dual-region-rdbms

## Goal

Create Claude Code commands that guide users through deploying Camunda 8 on AWS ECS Fargate across two regions. Commands collect user inputs, persist them as `terraform.tfvars`, and walk through deploy/verify/cleanup with concise Camunda platform context.

## Scope

### In Scope

- 5 commands in `.claude/commands/ecs-dual-region/`
- Terraform refactoring: extract hard-coded regions/CIDRs to variables
- New `networking_mode` variable: Transit Gateway or VPC Peering
- New `secondary_storage_type` variable: RDBMS (Aurora Global) or OpenSearch
- VPC Peering Terraform resources (new `vpc-peering.tf`)
- OpenSearch Terraform resources (new `opensearch.tf`, conditional)
- tfvars generation and incremental editing

### Out of Scope

- Failover/failback commands (future)
- Identity/Keycloak setup
- Optimize, WebModeler, Console components
- Automated health-check-driven failover

---

## 1. Terraform Refactoring

### 1.1 Extract Regions to Variables

Move hard-coded values from `variables.tf` locals block to proper variables:

```hcl
variable "region_0" {
  type        = string
  default     = "eu-west-2"
  description = "AWS region for the primary (owner) cluster"
}

variable "region_1" {
  type        = string
  default     = "eu-west-3"
  description = "AWS region for the secondary (accepter) cluster"
}

variable "region_0_cidr" {
  type        = string
  default     = "10.192.0.0/16"
  description = "VPC CIDR block for region 0"
}

variable "region_1_cidr" {
  type        = string
  default     = "10.202.0.0/16"
  description = "VPC CIDR block for region 1"
}
```

The `locals` block in `variables.tf` becomes computed from these variables instead of hard-coding values. Region full names (e.g., "london") are derived from a lookup map or the region code itself.

VPC creation stays inline using `terraform-aws-modules/vpc/aws` — no wrapper module. The upstream module is battle-tested; the value is in making the networking *between* VPCs modular.

### 1.2 Networking Mode

New variable:

```hcl
variable "networking_mode" {
  type        = string
  default     = "transit_gateway"
  description = "Cross-region networking: 'transit_gateway' or 'vpc_peering'"

  validation {
    condition     = contains(["transit_gateway", "vpc_peering"], var.networking_mode)
    error_message = "Must be 'transit_gateway' or 'vpc_peering'."
  }
}
```

**Existing `transit-gateway.tf`:** Wrap all resources with `count = var.networking_mode == "transit_gateway" ? 1 : 0`. Update references to use `[0]` indexing.

**New `vpc-peering.tf`:** Create with `count = var.networking_mode == "vpc_peering" ? 1 : 0`:
- `aws_vpc_peering_connection` (requester in region 0)
- `aws_vpc_peering_connection_accepter` (accepter in region 1)
- Route table entries in both VPCs pointing cross-region CIDR to peering connection
- DNS resolution enabled on both sides

Both modes produce the same outcome: cross-region VPC routing for Raft traffic and Aurora access.

### 1.3 Secondary Storage Type

New variable:

```hcl
variable "secondary_storage_type" {
  type        = string
  default     = "rdbms"
  description = "Camunda secondary storage: 'rdbms' (Aurora Global) or 'opensearch'"

  validation {
    condition     = contains(["rdbms", "opensearch"], var.secondary_storage_type)
    error_message = "Must be 'rdbms' or 'opensearch'."
  }
}
```

**Existing `aurora-global.tf` and `postgres_seed.tf`:** Wrap with `count = var.secondary_storage_type == "rdbms" ? 1 : 0`.

**New `opensearch.tf`:** Create with `count = var.secondary_storage_type == "opensearch" ? 1 : 0`:
- Uses existing `aws/modules/opensearch/` module (one independent domain per region)
- Unlike Aurora Global, OpenSearch has no built-in cross-region replication — each region gets its own domain, and Camunda brokers in each region export to both domains
- Security groups for OpenSearch access
- IAM policies for ECS tasks

**`camunda.tf` updates:** Conditionally set environment variables based on `secondary_storage_type`:
- RDBMS: `CAMUNDA_DATA_SECONDARYSTORAGE_TYPE=rdbms`, JDBC URL with AWS wrapper
- OpenSearch: `CAMUNDA_DATA_SECONDARYSTORAGE_TYPE=opensearch`, exporter URLs

### 1.4 locals.tf Changes

`locals.tf` retains only computed values:
- AZ lookups from data sources
- Naming prefixes (`${var.cluster_name}-r0`, etc.)
- Broker distribution math (even/odd IDs per region)
- Cluster sizing constants (8 brokers, RF=4, 8 partitions)

Region and CIDR values come from variables, not hard-coded locals.

---

## 2. Command Structure

```
.claude/commands/ecs-dual-region/
├── 1-configure.md        # Interactive wizard → terraform.tfvars
├── 2-deploy-infra.md     # terraform init + apply
├── 3-deploy-camunda.md   # Wait for ECS steady state + Raft quorum
├── 4-verify.md           # Health checks, topology, connectivity
├── 5-cleanup.md          # Ordered teardown
```

All commands follow the existing pattern from `.claude/commands/dual-region/` (EKS): markdown format, pre-checks, steps, verification, success criteria.

---

## 3. Command Details

### 3.1 — 1-configure.md

**Purpose:** Collect all deployment inputs and write `terraform.tfvars`.

**Pre-checks:**
- AWS CLI installed and credentials work
- Terraform installed

**Input collection (sequential questions with defaults):**

1. **Cluster name** — prefix for all resources (default: `"camunda-dr"`)
2. **AWS profile** — credential profile (default: null/default chain)
3. **Regions** — show defaults eu-west-2 + eu-west-3, allow override
4. **VPC CIDRs** — show defaults per region, allow override
5. **Networking mode** — Transit Gateway vs VPC Peering with trade-offs:
   - *Transit Gateway:* scalable hub, supports future multi-VPC, ~$0.05/GB + hourly. Best for production.
   - *VPC Peering:* simpler, no per-GB data transfer cost, direct connection. Best for dev/testing.
6. **Secondary storage** — RDBMS vs OpenSearch with Camunda context:
   - *RDBMS (Aurora Global):* simpler, cheaper, built-in cross-region replication and failover. Supports all Camunda components except Optimize.
   - *OpenSearch:* required if you need Optimize (process analytics). More infrastructure to manage.
7. **Access CIDRs** — load balancer access restriction (default: `0.0.0.0/0`)
8. **S3 force destroy** — allow terraform destroy to remove non-empty backup buckets (default: `true` for dev)

**tfvars output:** Show generated file, ask user to confirm before writing.

**Re-run behavior:** If tfvars exists, read it, show current values, ask which to change. Don't start from scratch.

**File written to:** `aws/containers/ecs-dual-region-fargate/terraform/clusters/terraform.tfvars`

Only non-default values are written (keeps tfvars minimal).

**End:** "Proceed with `/ecs-dual-region/2-deploy-infra`"

### 3.2 — 2-deploy-infra.md

**Purpose:** Deploy all infrastructure via Terraform.

**Pre-checks:**
- tfvars exists and has required values (`cluster_name`)
- Read `aws_profile` from tfvars for CLI commands

**Steps:**
1. `cd aws/containers/ecs-dual-region-fargate/terraform/clusters/`
2. `terraform init`
3. `terraform plan` — show summary of resources to create, ask user to confirm
4. `terraform apply -auto-approve` (after user confirms plan)

**Camunda context:** "This creates VPCs in both regions, cross-region networking (Transit Gateway or VPC Peering), the Aurora Global database (or OpenSearch), ECS clusters, load balancers, security groups, and all IAM roles. ECS services and Zeebe brokers start automatically after infrastructure is ready."

**Post-apply:**
- Show key outputs: ALB endpoints, NLB endpoints, Aurora endpoints, ECS cluster names, log group names
- Provide export block for user to copy-paste into shell

**End:** "Proceed with `/ecs-dual-region/3-deploy-camunda`"

### 3.3 — 3-deploy-camunda.md

**Purpose:** Monitor ECS services reaching steady state and Raft quorum formation.

**Pre-checks:**
- ECS clusters exist (`aws ecs describe-clusters --profile <profile>`)
- Aurora cluster is available

**Camunda context:** "Deploying 4 Zeebe brokers per region (8 total). Each broker owns partitions and participates in Raft consensus across regions. Expect ~20 minutes for Raft quorum formation. Connectors enable external system integration (REST, messaging) — one per region, connected to the local Zeebe gateway."

**Steps:**
1. Monitor ECS service events for orchestration clusters in both regions
2. Wait for running task count to match desired (4 per region)
3. Poll Zeebe topology endpoint via ALB: `curl http://<alb_region_0>/v2/topology`
4. Wait until all 8 brokers register and partitions elect leaders
5. Verify connectors services are running (1 per region)

**Troubleshooting guidance:**
- If tasks keep stopping: check CloudWatch logs via output log group name
- If Raft doesn't form: verify cross-region NLB connectivity, check security groups
- If Aurora connection fails: verify DB seed task succeeded, check IAM auth

**End:** "Proceed with `/ecs-dual-region/4-verify`"

### 3.4 — 4-verify.md

**Purpose:** Comprehensive health check of the dual-region deployment.

**Checks:**
1. **ECS services:** Running task counts match expected (4+4 orchestration, 1+1 connectors)
2. **Zeebe topology:** `curl <alb>/v2/topology` — 8 brokers, 8 partitions, leaders elected on every partition
3. **Aurora Global** (if RDBMS): cluster status, replication lag between primary and secondary
4. **OpenSearch** (if opensearch): cluster health green, indices present in both regions
5. **Cross-region connectivity:** both ALBs respond on port 8080, both gRPC NLBs reachable on 26500
6. **Optional workflow test:** deploy a simple process, create instance from region 0, verify completion visible from region 1

**Camunda context:** "Healthy topology: 8 brokers, 8 partitions, each partition with 4 replicas spread across both regions. Every partition should have exactly one leader."

**End:** "Deployment verified. To tear down, run `/ecs-dual-region/5-cleanup`"

### 3.5 — 5-cleanup.md

**Purpose:** Ordered teardown of all resources.

**Pre-checks:**
- Confirm user intent (destructive operation warning)
- Read `aws_profile` from tfvars

**Steps:**
1. Scale ECS services to 0 in both regions (graceful shutdown, prevents new connections)
2. Wait for running tasks to drain
3. `terraform destroy` — show plan, ask for confirmation
4. Verify no orphaned resources (ENIs, NLB targets that block VPC deletion)

**If destroy fails on VPC:**
- Guide user through manual ENI cleanup: `aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=<vpc_id>`
- Common cause: Lambda ENIs from CloudMap or NLB targets not fully deregistered
- Wait 5 minutes and retry, or manually delete orphaned ENIs

**End:** "All resources destroyed."

---

## 4. AWS Profile Handling

- **1-configure** collects the profile and writes `aws_profile` to tfvars
- **All subsequent commands** read tfvars to get the profile value
- AWS CLI commands use `--profile <value>` when set, omit flag when null/empty
- Terraform uses the profile via its provider configuration (already wired)

---

## 5. Camunda Platform Context Guidelines

Context is embedded at decision/action points, not as standalone documentation:

| Where | What | Example |
|-------|------|---------|
| Configure (storage choice) | Why RDBMS vs OpenSearch matters | "RDBMS supports all components except Optimize" |
| Configure (networking) | Cost/complexity trade-offs | "Transit Gateway ~$0.05/GB, VPC Peering free" |
| Deploy-camunda | What's happening | "8 brokers, RF=4 ensures both regions have full data" |
| Deploy-camunda | Timing expectations | "Raft quorum takes ~20 min across regions" |
| Verify | What healthy looks like | "Every partition should have exactly one leader" |

Keep it to 1-2 sentences per context point. Link to official Camunda docs for deep dives, don't replicate them.

---

## 6. Files to Create/Modify

### New Files
- `.claude/commands/ecs-dual-region/1-configure.md`
- `.claude/commands/ecs-dual-region/2-deploy-infra.md`
- `.claude/commands/ecs-dual-region/3-deploy-camunda.md`
- `.claude/commands/ecs-dual-region/4-verify.md`
- `.claude/commands/ecs-dual-region/5-cleanup.md`
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/vpc-peering.tf`
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/opensearch.tf`

### Modified Files
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/variables.tf` — add region vars, networking_mode, secondary_storage_type
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/locals.tf` — derive from variables instead of hard-coding
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/transit-gateway.tf` — add count conditional
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/aurora-global.tf` — add count conditional
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/postgres_seed.tf` — add count conditional
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/camunda.tf` — conditional env vars based on storage type
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/iam.tf` — conditional IAM policies based on storage type
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/security.tf` — conditional security groups for OpenSearch
- `aws/containers/ecs-dual-region-fargate/terraform/clusters/config.tf` — provider regions from variables

---

## 7. Implementation Order

1. **Terraform refactoring** — extract variables, update locals, update provider config
2. **Networking mode** — add conditionals to transit-gateway.tf, create vpc-peering.tf
3. **Secondary storage** — add conditionals to aurora/seed, create opensearch.tf, update camunda.tf env vars
4. **Commands** — write all 5 command files
5. **Test** — run `terraform validate` and `terraform plan` with both configurations
