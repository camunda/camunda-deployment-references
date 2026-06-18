# Configure ECS Dual-Region Deployment (Step 1/6)

Set up the deployment configuration by collecting inputs and writing tfvars files for the three Terraform states (vpc, infra, app).

## Camunda Context

Camunda 8 runs on ECS Fargate with Zeebe brokers distributed across two AWS regions. This provides:
- **High availability:** If one region fails, the other has a full copy of all data
- **8 brokers** with replication factor 4 ensures every partition exists in both regions
- **Connectors** handle external system integration (REST, messaging), one per region

## Terraform Layout

This reference uses a **3-state split** so customers can adopt only the layers they need:

- `terraform/vpc/` — VPCs, cross-region peering or Transit Gateway, optional Route 53 Resolver. Supports **BYO-VPC** for customers with existing networking.
- `terraform/infra/` — Aurora Global / OpenSearch, ECS clusters, ALB/NLBs, KMS, S3, secrets, IAM. Reads vpc outputs via `terraform_remote_state`. Slow (~15-20 min), rarely changes.
- `terraform/app/` — Camunda orchestration-cluster + connectors ECS task definitions and services. ~30s. Reads infra outputs.

## Pre-Checks

1. Verify AWS CLI is installed:
```bash
aws --version
```

2. Verify Terraform is installed:
```bash
terraform --version
```

3. Verify AWS credentials work:
```bash
aws sts get-caller-identity
```

## Configuration

### Step 1: Choose VPC source

Ask first: **"Do you want Terraform to create new VPCs (greenfield) or use existing VPCs (BYO-VPC)?"**

- **Greenfield** — Terraform creates two VPCs, subnets, NAT/IGW, then peering/TGW. Best for fresh demos and dev.
- **BYO-VPC** — You supply existing VPC IDs, subnet IDs, CIDRs, and route table IDs. Best for customers with established networking (transit hubs, IPAM allocations, shared services).

Check if `aws/containers/ecs-dual-region-fargate/terraform/vpc/terraform.tfvars` already exists.
- If yes: read it, show current values, ask which to change.
- If no: collect all inputs fresh.

### Step 2: Collect common inputs (both modes)

Ask these questions **one at a time**, showing the default value. Only write non-default values to tfvars.

1. **Cluster name** (required, no default): Prefix for all AWS resources. Must be lowercase, alphanumeric + hyphens, max 20 chars.

2. **AWS profile** (default: null — uses default credential chain): Which AWS credential profile to use.

3. **Region 0** (default: `eu-west-2` — London): Primary region with Aurora writer and Zeebe brokers 0,2,4,6.

4. **Region 1** (default: `eu-west-3` — Paris): Secondary region with Aurora read replicas and Zeebe brokers 1,3,5,7.

5. **Networking mode** (default: `transit_gateway`):
   - **Transit Gateway** — Scalable hub, supports future multi-VPC topologies. ~$0.05/GB + hourly charge. Best for production.
   - **VPC Peering** — Simpler, no per-GB data transfer cost, direct 1:1 connection. Best for dev/testing.

6. **Secondary storage** (default: `rdbms`):
   - **RDBMS (Aurora Global)** — Simpler, cheaper, built-in cross-region replication and failover. Supports all Camunda components except Optimize.
   - **OpenSearch** — Required if you need Optimize (process analytics). One independent domain per region, brokers export to both.

7. **Restrict load balancer access** (default: `0.0.0.0/0`): CIDR blocks allowed to reach ALB/NLB. Comma-separated for multiple.

8. **Custom Camunda image** (default: `camunda/camunda:8.10.0-alpha1`): Override the Camunda container image (e.g. for private registry or pinned version).

### Step 3a: Greenfield-only inputs

Only ask these when the user chose greenfield in step 1:

9. **VPC CIDR for region 0** (default: `10.192.0.0/16`): Must not overlap with region 1 CIDR.

10. **VPC CIDR for region 1** (default: `10.202.0.0/16`): Must not overlap with region 0 CIDR.

11. **Single NAT gateway** (default: `true` for cost savings): Use one NAT gateway per region instead of one per AZ. Not recommended for production HA.

### Step 3b: BYO-VPC-only inputs

Only ask these when the user chose BYO-VPC in step 1. **All are required** — validation in the vpc state will reject incomplete tfvars at plan time.

9. **Region 0 VPC ID** (format: `vpc-xxxxxxxx`).
10. **Region 0 VPC CIDR** (must match the existing VPC).
11. **Region 0 private subnet IDs** (≥3 across distinct AZs, format: `subnet-xxxxxxxx`, comma-separated). Used by ECS tasks AND Aurora.
12. **Region 0 public subnet IDs** (≥3 across distinct AZs). Used by ALBs and NAT gateways — must have an IGW route.
13. **Region 0 private route table IDs** (≥1, format: `rtb-xxxxxxxx`). Peering/TGW routes will be added to these.
14. **Region 1 VPC ID** (same format).
15. **Region 1 VPC CIDR**.
16. **Region 1 private subnet IDs** (≥3 distinct AZs).
17. **Region 1 public subnet IDs** (≥3 distinct AZs).
18. **Region 1 private route table IDs** (≥1).

Remind the user: their VPCs must satisfy the contract in `terraform/vpc/README.md` → "BYO-VPC requirements". Validation at plan time will catch missing/malformed inputs but cannot verify subnet AZ topology or routing.

### Step 4: S3 force destroy (both modes)

19. **S3 force destroy** (default: `true` for dev): Allow `terraform destroy` to remove non-empty backup buckets.

### Step 5: Write tfvars (three files)

After collecting all inputs, generate the three tfvars files and show them to the user for review before writing.

**File 1 — `terraform/vpc/terraform.tfvars`** (vpc inputs; same file for both modes):

Greenfield:
```hcl
# terraform/vpc/terraform.tfvars — generated by /ecs-dual-region/1-configure
cluster_name       = "my-test"
aws_profile        = "default"
region_0           = "eu-west-2"
region_1           = "eu-west-3"
networking_mode    = "vpc_peering"
single_nat_gateway = true
```

BYO-VPC:
```hcl
# terraform/vpc/terraform.tfvars — generated by /ecs-dual-region/1-configure
cluster_name      = "my-test"
aws_profile       = "default"
region_0          = "eu-west-2"
region_1          = "eu-west-3"
networking_mode   = "transit_gateway"
byo_vpc           = true

region_0_vpc_id                  = "vpc-0123456789abcdef0"
region_0_vpc_cidr                = "10.50.0.0/16"
region_0_private_subnet_ids      = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
region_0_public_subnet_ids       = ["subnet-ddd", "subnet-eee", "subnet-fff"]
region_0_private_route_table_ids = ["rtb-aaa", "rtb-bbb", "rtb-ccc"]

region_1_vpc_id                  = "vpc-0123456789abcdef1"
region_1_vpc_cidr                = "10.60.0.0/16"
region_1_private_subnet_ids      = ["subnet-ggg", "subnet-hhh", "subnet-iii"]
region_1_public_subnet_ids       = ["subnet-jjj", "subnet-kkk", "subnet-lll"]
region_1_private_route_table_ids = ["rtb-ddd", "rtb-eee", "rtb-fff"]
```

**File 2 — `terraform/infra/terraform.tfvars`** (infra inputs, both modes):
```hcl
# terraform/infra/terraform.tfvars — generated by /ecs-dual-region/1-configure
cluster_name           = "my-test"
aws_profile            = "default"
region_0               = "eu-west-2"
region_1               = "eu-west-3"
secondary_storage_type = "rdbms"
s3_force_destroy       = true
limit_access_to_cidrs  = ["10.0.0.0/8"]
```

**File 3 — `terraform/app/terraform.tfvars`** (app inputs):
```hcl
# terraform/app/terraform.tfvars — generated by /ecs-dual-region/1-configure
aws_profile   = "default"
camunda_image = "camunda/camunda:8.10.0-alpha1"
# infra_state_path defaults to "../infra/terraform.tfstate" — override if using S3 backend
```

Only set `aws_profile` if it was set. Only set `camunda_image` if the user chose a custom value. `cluster_name`, `region_0`, `region_1` must match between vpc and infra tfvars — the vpc state output is informational only.

## Success

Tell the user: "Configuration saved to `terraform/vpc/terraform.tfvars`, `terraform/infra/terraform.tfvars`, and `terraform/app/terraform.tfvars`. Proceed with `/ecs-dual-region/2-deploy-vpc`."
