# Deploy ECS Dual-Region VPC State (Step 2/6)

Apply the **vpc** Terraform layer: VPCs (greenfield only), cross-region peering or Transit Gateway, and optional Route 53 Resolver. This step runs in both **greenfield** and **BYO-VPC** modes — in BYO mode it creates no VPC resources, only peering/TGW between the supplied VPCs.

## Pre-Checks

1. Verify vpc tfvars exists and read the configuration:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/vpc/terraform.tfvars
```
If missing, tell the user to run `/ecs-dual-region/1-configure` first.

2. Note the `byo_vpc` flag in tfvars — it determines what gets created:
   - `byo_vpc = false` (greenfield) — Terraform creates two VPCs, subnets, NAT/IGW, then peering/TGW.
   - `byo_vpc = true` (BYO) — Terraform skips VPC creation and only wires peering/TGW between the supplied VPC IDs.

3. Extract `aws_profile` from tfvars for CLI commands. If set, use `--profile <value>`. If null/empty, omit the flag.

## Camunda Context

The vpc layer owns everything network-shaped that *can be* customer-supplied:

- **2 VPCs** with private/public subnets across 3 AZs each (greenfield only)
- **Cross-region link** (Transit Gateway or VPC Peering) carrying Zeebe Raft (port 26502) and Camunda's cross-region Aurora writes
- **Route 53 Resolver endpoints** (optional) for cross-region Service Connect DNS — requires `route53resolver:CreateResolverEndpoint` IAM permission

In BYO mode, the customer's VPCs must satisfy the contract documented in `terraform/vpc/README.md` → "BYO-VPC requirements" (≥3 private + ≥3 public subnets across distinct AZs per region, plus route table IDs for the cross-region routes). Validation is enforced by `check` blocks at plan time — a malformed BYO tfvars will fail fast.

## Steps

1. **Initialize Terraform (vpc state):**
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/vpc
terraform init
```
If using S3 backend, pass `-backend-config=...`. Otherwise local state is fine for dev (a `config_override.tf` with `backend "local" {}` is the established pattern).

2. **Plan:**
```bash
terraform plan
```
Expected resource count:
- Greenfield + `transit_gateway`: ~25-30 resources (2 VPCs, 6 subnets, 2 NAT, 2 IGW, TGW peering, routes)
- Greenfield + `vpc_peering`: ~20-25 resources (VPC peering instead of TGW)
- BYO + `transit_gateway`: ~8-10 resources (TGW peering, attachments, routes only)
- BYO + `vpc_peering`: ~5-7 resources (peering + routes only)

Show the user the count and ask them to confirm.

3. **Apply:**
```bash
terraform apply -auto-approve
```
Greenfield takes 3-5 minutes (NAT gateway provisioning). BYO mode is fast (< 1 minute).

4. **Show key outputs:**
```bash
terraform output
```
The contract consumed by `infra/` in step 3 includes:
- `region_0_vpc_id` / `region_1_vpc_id`
- `region_0_private_subnet_ids` / `region_1_private_subnet_ids`
- `region_0_public_subnet_ids` / `region_1_public_subnet_ids`
- `region_0_vpc_cidr` / `region_1_vpc_cidr`
- `networking_mode`
- `region_0_transit_gateway_id` / `region_1_transit_gateway_id` (or `vpc_peering_connection_id`)
- `region_0_internet_gateway_id` / `region_1_internet_gateway_id` (null in BYO mode)

## Troubleshooting

- **`check` block failure on `byo_vpc_required_inputs`:** BYO tfvars missing a required field. Re-run `/ecs-dual-region/1-configure` to fix.
- **`check` block failure on `create_vpc_inputs_clean`:** `byo_vpc = false` but stray BYO variables are set. Clear them or set `byo_vpc = true`.
- **`route53resolver:CreateResolverEndpoint` denied:** The Route 53 Resolver toggle requires extra IAM. Set `enable_cross_region_dns_resolver = false` in tfvars and re-apply — Zeebe Raft and Connectors work without it (they reach cross-region via NLB DNS names).
- **NAT gateway slow / costs unexpected:** Greenfield with `single_nat_gateway = false` provisions one NAT per AZ per region (6 total). Set `single_nat_gateway = true` for dev to bring that to 2.

## Success

Tell the user: "VPC layer deployed. Proceed with `/ecs-dual-region/3-deploy-infra`."
