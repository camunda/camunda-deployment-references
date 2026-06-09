# ECS Dual-Region Fargate — VPC State Split & BYO-VPC Design

**Date:** 2026-06-09
**Status:** Approved (open questions resolved 2026-06-09)
**Branch:** feat/ecs-dual-region-rdbms

## Goal

Split the existing 2-state Terraform layout (`infra/` + `app/`) into a 3-state layout (`vpc/` + `infra/` + `app/`) so that customers adopting this reference architecture can either:

- **Greenfield** — let Terraform create all VPCs, subnets, NAT/IGWs, cross-region peering, and Route 53 Resolver endpoints, OR
- **BYO-VPC** — supply IDs of pre-existing VPCs and subnets in one or both regions and have Terraform consume them as inputs.

`infra/` must have exactly one input shape regardless of mode — it always reads from the `vpc/` remote state. All branching lives inside `vpc/`.

## Motivation

Many enterprise customers already own VPCs (existing transit hubs, IPAM allocations, shared services). The current layout assumes greenfield: `infra/` creates the VPCs itself. Forcing customers to either delete-and-recreate networking or hack around the module is the wrong default. By moving VPC concerns to their own state with a BYO mode, we:

- Match the realistic customer adoption path.
- Avoid two code paths inside `infra/`.
- Keep `app/` totally unaware of how networking arrived.

## Scope

### In Scope

- New `terraform/vpc/` state with two modes (create / BYO) selected via `var.byo_vpc`.
- Validation that BYO inputs are complete and well-formed at plan time.
- Refactor of `terraform/infra/` to consume VPC state via `terraform_remote_state` only.
- Update slash-commands skill set from 5 to 6 steps to include `2-deploy-vpc`.
- Update procedure scripts (`export_environment_prerequisites.sh`, `failback.sh`) to know about the three states.
- New `terraform/vpc/README.md` (terraform-docs auto-generated).
- Documentation updates: top-level `README.md`, this spec, BYO-VPC requirements section.

### Out of Scope

- BYO cross-region peering / TGW. `vpc/` always creates the peering between the two VPCs it knows about (whether those VPCs are created or supplied). Future toggle if customers push back.
- State migration of the existing `feat/ecs-dual-region-rdbms` dev deploy. The user will redeploy from scratch after merge.
- Customer-owned KMS keys, secrets, IAM, or load balancers. `infra/` continues to own all of those.

---

## 1. New `terraform/vpc/` State

### 1.1 Directory layout

```
terraform/vpc/
├── byo.tf              # BYO data sources + check blocks
├── vpc.tf              # Create path: terraform-aws-modules/vpc/aws calls, conditional
├── transit-gateway.tf  # Always creates peering/TGW between local.vpc_id_{0,1}
├── vpc-peering.tf
├── dns.tf              # Route 53 Resolver endpoints (depends on subnet IDs)
├── outputs.tf          # Single contract for infra/
├── variables.tf        # All input vars (greenfield + BYO)
├── locals.tf           # Resolves local.region_*_vpc_id from byo_vpc toggle
├── config.tf           # Provider + S3 backend declaration
└── README.md           # terraform-docs auto-generated
```

### 1.2 Toggle: `var.byo_vpc`

```hcl
variable "byo_vpc" {
  type        = bool
  default     = false
  description = "If true, consume existing VPC IDs from var.region_{0,1}_vpc_id and friends. If false, create VPCs via terraform-aws-modules/vpc/aws."
}
```

When `byo_vpc = false` (default, greenfield):
- VPC module instantiations run with `count = 1`.
- BYO variables (`region_*_vpc_id`, etc.) must be empty — enforced by a `check` block.

When `byo_vpc = true`:
- VPC module instantiations are skipped (`count = 0`).
- All BYO variables must be populated — enforced by a `check` block.
- `vpc/` still applies peering/TGW between the supplied VPC IDs.
- `vpc/` still creates Route 53 Resolver endpoints in the supplied subnets (requires `route53resolver:CreateResolverEndpoint` IAM permission on the apply principal — same as today's `enable_cross_region_dns_resolver` variable).

### 1.3 Locals: single source of truth

```hcl
locals {
  region_0_vpc_id              = var.byo_vpc ? var.region_0_vpc_id              : module.vpc_region_0[0].vpc_id
  region_0_private_subnet_ids  = var.byo_vpc ? var.region_0_private_subnet_ids  : module.vpc_region_0[0].private_subnets
  region_0_database_subnet_ids = var.byo_vpc ? var.region_0_database_subnet_ids : module.vpc_region_0[0].database_subnets
  region_0_vpc_cidr            = var.byo_vpc ? var.region_0_vpc_cidr            : module.vpc_region_0[0].vpc_cidr_block
  # ... mirror for region_1
}
```

Everything downstream (peering, TGW, resolver) refers to `local.region_0_vpc_id`, never to the module output or the variable directly.

### 1.4 Output contract (consumed by `infra/`)

```hcl
output "region_0_vpc_id"                    { value = local.region_0_vpc_id }
output "region_0_vpc_cidr"                  { value = local.region_0_vpc_cidr }
output "region_0_private_subnet_ids"        { value = local.region_0_private_subnet_ids }
output "region_0_database_subnet_ids"       { value = local.region_0_database_subnet_ids }
output "region_0_public_subnet_ids"         { value = local.region_0_public_subnet_ids }
output "region_0_private_route_table_ids"   { value = local.region_0_private_route_table_ids }
output "region_0_database_route_table_ids"  { value = local.region_0_database_route_table_ids }
# Mirror for region_1.

output "networking_mode"                    { value = var.networking_mode }
output "transit_gateway_id_region_0"        { value = local.transit_gateway_id_region_0 }
output "transit_gateway_id_region_1"        { value = local.transit_gateway_id_region_1 }
output "vpc_peering_connection_id"          { value = local.vpc_peering_connection_id }
output "route53_resolver_endpoint_region_0" { value = local.route53_resolver_endpoint_region_0 }
output "route53_resolver_endpoint_region_1" { value = local.route53_resolver_endpoint_region_1 }
output "region_0_internet_gateway_id"       { value = local.region_0_internet_gateway_id }
output "region_1_internet_gateway_id"       { value = local.region_1_internet_gateway_id }
```

Naming convention for new outputs: `region_N_<thing>` (e.g. `region_0_vpc_id`, `region_1_internet_gateway_id`). Mixed-style outputs from earlier code (`transit_gateway_id_region_0`, etc.) are renamed during PR 1.

These are the only fields `infra/` is allowed to read. The contract is frozen at PR-1 merge; later additions require an output that doesn't break existing consumers.

## 2. Validation

### 2.1 Per-variable: shape checks (TF ≥ 1.6)

```hcl
variable "region_0_vpc_id" {
  type    = string
  default = ""
  validation {
    condition     = var.region_0_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.region_0_vpc_id))
    error_message = "region_0_vpc_id must match vpc-xxxxxxxx (8-17 hex chars) or be empty."
  }
}

variable "region_0_private_subnet_ids" {
  type    = list(string)
  default = []
  validation {
    condition = length(var.region_0_private_subnet_ids) == 0 || alltrue([
      for s in var.region_0_private_subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))
    ])
    error_message = "Each region_0_private_subnet_ids entry must match subnet-xxxxxxxx."
  }
}
```

Same pattern for `region_0_database_subnet_ids`, `region_0_public_subnet_ids`, `region_1_*`, and `region_0_vpc_cidr` (`cidrnetmask()` succeeds or empty).

### 2.2 Cross-variable: `check` blocks (TF ≥ 1.5)

```hcl
check "byo_vpc_required_inputs" {
  assert {
    condition = !var.byo_vpc || (
      var.region_0_vpc_id              != "" &&
      var.region_0_vpc_cidr            != "" &&
      length(var.region_0_private_subnet_ids)  >= 3 &&
      length(var.region_0_database_subnet_ids) >= 3 &&
      var.region_1_vpc_id              != "" &&
      var.region_1_vpc_cidr            != "" &&
      length(var.region_1_private_subnet_ids)  >= 3 &&
      length(var.region_1_database_subnet_ids) >= 3
    )
    error_message = "byo_vpc = true requires region_{0,1}_vpc_id, region_{0,1}_vpc_cidr, and ≥3 private subnets and ≥3 database subnets per region across distinct AZs. See terraform/vpc/README.md → 'BYO-VPC requirements'."
  }
}

check "create_vpc_inputs_clean" {
  assert {
    condition = var.byo_vpc || (
      var.region_0_vpc_id == "" &&
      var.region_1_vpc_id == "" &&
      length(var.region_0_private_subnet_ids) == 0 &&
      length(var.region_1_private_subnet_ids) == 0
    )
    error_message = "byo_vpc = false but BYO variables are set. They would be silently ignored. Clear them or set byo_vpc = true."
  }
}
```

`check` block failures surface at plan time, before any AWS calls.

## 3. BYO-VPC Requirements

A customer's existing VPCs must satisfy:

| Resource | Region 0 | Region 1 |
|---|---|---|
| VPC | 1 | 1 |
| Non-overlapping CIDRs | yes | yes |
| Private subnets (egress via NAT) | ≥ 3, distinct AZs | ≥ 3, distinct AZs |
| Database subnets (no IGW route) | ≥ 3, distinct AZs | ≥ 3, distinct AZs |
| Public subnets (for ALB / NAT) | ≥ 3, distinct AZs, with IGW route | ≥ 3, distinct AZs, with IGW route |
| Route table IDs for private subnets | passed in via var | passed in via var |
| Sufficient free IP space in each subnet | ≥ /27 recommended | ≥ /27 recommended |
| Permissions on the apply principal | `ec2:CreateRoute`, `ec2:CreateTransitGatewayPeeringAttachment` (or VPC peering equivalents), `route53resolver:*` | same |

A "requirements for BYO-VPC" section will be added to `terraform/vpc/README.md` reflecting this table.

## 4. `terraform/infra/` Changes

### 4.1 New variable

```hcl
variable "vpc_state_path" {
  type        = string
  default     = "../vpc/terraform.tfstate"
  description = "Path to the vpc terraform state file (local backend) or S3 key."
}
```

### 4.2 Remote state + locals

```hcl
data "terraform_remote_state" "vpc" {
  backend = "local"
  config  = { path = var.vpc_state_path }
}

locals {
  vpc = data.terraform_remote_state.vpc.outputs
}
```

### 4.3 Mechanical reference swap

Every `module.vpc_region_0.<x>` → `local.vpc.region_0_<x>`. Affected files (best estimate):

- `aurora-global.tf` — subnet IDs for DB subnet group
- `ecs.tf` — none directly (cluster is region-scoped)
- `lb.tf` — subnet IDs for ALB/NLB
- `opensearch.tf` — subnet IDs
- `postgres_seed.tf` — subnet IDs + security group
- `security.tf` — VPC IDs and CIDRs
- `iam.tf` — no change

### 4.4 Removed from `infra/`

- `vpc.tf`
- `transit-gateway.tf`
- `vpc-peering.tf`
- `dns.tf`
- VPC-related variables from `variables.tf`: `region_0_cidr`, `region_1_cidr`, `networking_mode`, `single_nat_gateway`, `enable_cross_region_dns_resolver`. They move to `vpc/`.

## 5. Slash Commands: 5 → 6

| # | Skill name | Replaces / new | Summary |
|---|---|---|---|
| 1 | `1-configure` | replaces existing | Asks BYO vs greenfield. Writes up to 3 tfvars: `vpc/`, `infra/`, `app/`. |
| 2 | `2-deploy-vpc` | **new** | `cd terraform/vpc && init + plan + apply`. Runs in both modes — BYO mode applies a state with zero AWS resources and re-exported outputs. |
| 3 | `3-deploy-infra` | renamed from `2-deploy-infra` | Reads `vpc/` remote state. Same flow as today. |
| 4 | `4-deploy-camunda` | renamed from `3-deploy-camunda` | Unchanged otherwise. |
| 5 | `5-verify` | renamed from `4-verify` | Now pulls VPC IDs from `vpc/`, Aurora IDs from `infra/`, ALB endpoints from `app/`. |
| 6 | `6-cleanup` | renamed from `5-cleanup` | Destroy order: `app/` → `infra/` → `vpc/`. |

### 5.1 `1-configure` decision tree

```
Q: Greenfield or BYO-VPC?
├── greenfield → ask region/CIDR/NAT/networking_mode questions →
│                write vpc/terraform.tfvars with all greenfield inputs
└── BYO        → ask for region_{0,1}_vpc_id, _vpc_cidr, _private_subnet_ids,
                 _database_subnet_ids, _public_subnet_ids, _private_route_table_ids,
                 networking_mode → write vpc/terraform.tfvars with byo_vpc=true
```

In both branches, `infra/terraform.tfvars` and `app/terraform.tfvars` are written with the same content as today.

### 5.2 Procedure script updates

`procedure/export_environment_prerequisites.sh` and `procedure/failback.sh` currently default `TF_DIR=terraform/clusters`. Replace with:

```sh
VPC_DIR="${VPC_DIR:-${SCRIPT_DIR}/../terraform/vpc}"
INFRA_DIR="${INFRA_DIR:-${SCRIPT_DIR}/../terraform/infra}"
APP_DIR="${APP_DIR:-${SCRIPT_DIR}/../terraform/app}"
```

Each output read is then sourced from the appropriate dir.

## 6. PR Breakdown

1. **PR 1** — Create `terraform/vpc/` with both modes, validation, and the output contract. Validate-only (no removals from `infra/`). Reviewer checks: contract completeness, validation coverage, BYO requirements doc.
2. **PR 2** — Refactor `infra/` to consume `vpc/` remote state. Mechanical reference swap. Files deleted from `infra/`. `terraform plan` in `infra/` against a fresh `vpc/` apply should report 0 unrelated changes.
3. **PR 3** — Slash commands (6 commands), procedure script updates, top-level README updates, this spec moves from Draft → Approved.

Each PR is independently mergeable to `main` (PR 1 adds a dead-but-valid `vpc/` directory; PR 2 doesn't break until PR 3's commands ship — but `infra/` continues to work as long as someone applies `vpc/` first).

## 7. Validation Plan

Pre-merge:

1. `terraform validate` in each of `vpc/`, `infra/`, `app/`.
2. `terraform plan` greenfield path with default tfvars — non-zero adds in `vpc/`, then `infra/` reads the state cleanly.
3. `terraform plan` with `byo_vpc = true` and fake-but-syntactically-valid IDs — plan should succeed and show no VPC resources being created; only peering + resolver if applicable.
4. `terraform plan` with `byo_vpc = true` and missing inputs — plan should fail with the `check "byo_vpc_required_inputs"` error message.
5. `terraform plan` with `byo_vpc = false` but a stray `region_0_vpc_id` set — plan should fail with the `check "create_vpc_inputs_clean"` error message.
6. `terraform plan` with malformed VPC ID (`var.region_0_vpc_id = "nope"`) — variable validation rejects with the regex message.

Post-merge (separate validation run by the user):

7. Apply greenfield end-to-end on the same dev account used today. Confirm 133-resource baseline shifts to roughly the same total split across `vpc/` (~30) and `infra/` (~100).
8. Apply BYO-VPC against a pair of manually-created throwaway VPCs in a sandbox account, confirm full ECS dual-region deploy works.

## 8. Open Questions (resolved)

- **Q1.** ✅ Yes — expose `region_{0,1}_internet_gateway_id` in the contract. Cheap and future-proofs failover scripts.
- **Q2.** ✅ Yes — `enable_cross_region_dns_resolver` toggle moves to `vpc/` unchanged.
- **Q3.** ✅ Naming convention is `region_N_<thing>` (e.g. `region_0_vpc_id`). Existing outputs using the inverted form (`transit_gateway_id_region_0`) get renamed during PR 1.

## 9. References

- Existing 2-state split commit: `209499ea` (`refactor: split Terraform into infra and app states`)
- Existing commands design: `docs/superpowers/specs/2026-04-16-ecs-dual-region-commands-design.md`
- AWS docs — Aurora Global Database networking: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html
- Terraform `check` blocks: https://developer.hashicorp.com/terraform/language/checks
