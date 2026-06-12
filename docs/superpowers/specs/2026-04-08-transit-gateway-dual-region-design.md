# Transit Gateway Support for EKS Dual-Region

## Overview

Add AWS Transit Gateway as an alternative to VPC Peering for cross-region connectivity in the EKS dual-region reference architecture. Users select the connectivity method via a single Terraform variable while the rest of the stack (DNS chaining, Helm values, procedure scripts) remains unchanged.

## Decision Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Replace or alternative? | Alternative (configurable) | Users may prefer either approach depending on their environment |
| Region scalability | N-region capable | TGW's main advantage; aligns with 3+ region recommendation |
| Code organization | Separate files (`vpc-peering.tf` / `transit-gateway.tf`) | Clean separation; each method self-contained |
| TGW creation | Out of scope (user-provided) | Assumes TGW already exists |
| TGW input | ID required, RAM share ARN optional | Covers single-account and cross-account (landing zone) patterns |
| DNS approach | CoreDNS chaining unchanged | Keeps scope focused; works identically over both connectivity types |
| Toggle mechanism | `connectivity_type` variable with `count` guards | Discoverable, CI-friendly, self-documenting |

## Variables

Add to `aws/kubernetes/eks-dual-region/terraform/clusters/variables.tf`:

```hcl
variable "connectivity_type" {
  type        = string
  description = "Type of connectivity between the two VPCs. 'peering' uses VPC Peering, 'transit-gateway' uses an existing AWS Transit Gateway."
  default     = "peering"
  validation {
    condition     = contains(["peering", "transit-gateway"], var.connectivity_type)
    error_message = "connectivity_type must be 'peering' or 'transit-gateway'."
  }
}

variable "transit_gateway_id" {
  type        = string
  description = "ID of an existing Transit Gateway to attach VPCs to. Required when connectivity_type is 'transit-gateway'."
  default     = null
}

variable "transit_gateway_ram_share_arn" {
  type        = string
  description = "ARN of a RAM share for the Transit Gateway. Required when the TGW is in a different AWS account."
  default     = null
}
```

A validation ensures `transit_gateway_id` is set when `connectivity_type = "transit-gateway"`.

## VPC Peering Changes (`vpc-peering.tf`)

All 7 existing resources receive a `count` guard:

```hcl
count = var.connectivity_type == "peering" ? 1 : 0
```

For resources already using `count` (route table iteration), the pattern becomes:

```hcl
count = var.connectivity_type == "peering" ? length(module.eks_cluster_region_X.private_route_table_ids) : 0
```

No other changes to this file.

## Transit Gateway File (`transit-gateway.tf`)

New file with all resources guarded by `count = var.connectivity_type == "transit-gateway" ? 1 : 0`.

### Data Source (new)

```hcl
data "aws_caller_identity" "current" {
  count = var.connectivity_type == "transit-gateway" && var.transit_gateway_ram_share_arn != null ? 1 : 0
}
```

### RAM Share Acceptance (optional, cross-account)

```hcl
resource "aws_ram_principal_association" "tgw" {
  count              = var.connectivity_type == "transit-gateway" && var.transit_gateway_ram_share_arn != null ? 1 : 0
  resource_share_arn = var.transit_gateway_ram_share_arn
  principal          = data.aws_caller_identity.current[0].account_id
}
```

### TGW VPC Attachments

One per region, targeting private subnets:

```hcl
resource "aws_ec2_transit_gateway_vpc_attachment" "region_0" {
  count              = var.connectivity_type == "transit-gateway" ? 1 : 0
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = module.eks_cluster_region_0.vpc_id
  subnet_ids         = module.eks_cluster_region_0.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-${local.owner.region_full_name}-tgw-attachment"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "region_1" {
  count              = var.connectivity_type == "transit-gateway" ? 1 : 0
  provider           = aws.accepter
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = module.eks_cluster_region_1.vpc_id
  subnet_ids         = module.eks_cluster_region_1.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-${local.accepter.region_full_name}-tgw-attachment"
  }
}
```

### Route Table Updates

Mirror the peering routes but use `transit_gateway_id` instead of `vpc_peering_connection_id`:

- `aws_route.owner_tgw` — owner main route table
- `aws_route.owner_private_tgw` — owner private route tables (count = N route tables)
- `aws_route.accepter_tgw` — accepter main route table
- `aws_route.accepter_private_tgw` — accepter private route tables (count = N route tables)

All routes use `destination_cidr_block` pointing to the other VPC's CIDR.

### Security Groups

Identical rules to peering — allow all traffic (`ip_protocol = -1`) from the other VPC's CIDR block on each cluster's primary security group. Named with `_tgw` suffix to avoid conflicts.

## Unchanged Components

The following are independent of the connectivity layer and require no changes:

- **CoreDNS chaining** — DNS forwarding works over any IP-level connectivity
- **Helm values** — Zeebe contact points and ES exporters use DNS names
- **Procedure scripts** — `generate_core_dns_entry.sh`, `sync_elasticsearch_passwords.sh`, etc.
- **Elasticsearch / S3 backup** — operates at the application layer

## Testing

### Golden File Tests

Add a new fixture for the TGW path:

```
test/golden/transit-gateway.tfvars
```

```hcl
connectivity_type  = "transit-gateway"
transit_gateway_id = "tgw-0123456789abcdef0"
```

The golden plan captures TGW resources instead of peering resources.

### Integration Tests (Go/Terratest)

- Add `CONNECTIVITY_TYPE` environment variable to select the path in `TestClusterSetup`
- TGW integration tests require a pre-existing Transit Gateway in the test AWS account
- DNS chaining, Camunda deployment, and failover/failback tests are unchanged

## Documentation

Update in the dual-region directory:

- **README.md** — Document `connectivity_type` variable, prerequisites for TGW, example `.tfvars`
- **DEVELOPER.md** — Testing instructions for both connectivity paths

## File Changes Summary

| File | Action |
|------|--------|
| `terraform/clusters/variables.tf` | Add 3 variables |
| `terraform/clusters/vpc-peering.tf` | Add `count` guards to all resources |
| `terraform/clusters/transit-gateway.tf` | New file (includes `aws_caller_identity` data source) |
| `test/golden/transit-gateway.tfvars` | New fixture |
| `README.md` | Update with TGW documentation |
| `DEVELOPER.md` | Update with TGW testing instructions |
