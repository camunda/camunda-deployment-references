# Transit Gateway Support for EKS Dual-Region Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AWS Transit Gateway as a configurable alternative to VPC Peering for cross-region connectivity in the EKS dual-region reference architecture.

**Architecture:** A `connectivity_type` variable (`"peering"` or `"transit-gateway"`) toggles between two separate Terraform files using `count` guards. Transit Gateway assumes a pre-existing TGW and only manages VPC attachments, routes, and security groups. DNS chaining, Helm values, and procedure scripts are unchanged.

**Tech Stack:** Terraform (AWS provider ~> 6.0), HCL

---

### Task 1: Add connectivity variables to `variables.tf`

**Files:**
- Modify: `aws/kubernetes/eks-dual-region/terraform/clusters/variables.tf:72-76`

- [ ] **Step 1: Add the three new variables at the end of `variables.tf`**

Append after the `default_tags` variable block (line 76):

```hcl

################################
# Connectivity                 #
################################

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

- [ ] **Step 2: Validate the syntax**

Run:
```bash
cd aws/kubernetes/eks-dual-region/terraform/clusters && terraform fmt -check
```
Expected: no output (already formatted) or file name if formatting needed.

- [ ] **Step 3: Format if needed**

Run:
```bash
cd aws/kubernetes/eks-dual-region/terraform/clusters && terraform fmt variables.tf
```

- [ ] **Step 4: Commit**

```bash
git add aws/kubernetes/eks-dual-region/terraform/clusters/variables.tf
git commit -m "feat(dual-region): add connectivity_type and transit gateway variables"
```

---

### Task 2: Add `count` guards to `vpc-peering.tf`

**Files:**
- Modify: `aws/kubernetes/eks-dual-region/terraform/clusters/vpc-peering.tf`

- [ ] **Step 1: Add `count` to `aws_vpc_peering_connection.owner` (line 11)**

Change:
```hcl
resource "aws_vpc_peering_connection" "owner" {
  vpc_id      = module.eks_cluster_region_0.vpc_id
  peer_vpc_id = module.eks_cluster_region_1.vpc_id
  peer_region = local.accepter.region
  auto_accept = false
```

To:
```hcl
resource "aws_vpc_peering_connection" "owner" {
  count = var.connectivity_type == "peering" ? 1 : 0

  vpc_id      = module.eks_cluster_region_0.vpc_id
  peer_vpc_id = module.eks_cluster_region_1.vpc_id
  peer_region = local.accepter.region
  auto_accept = false
```

- [ ] **Step 2: Add `count` to `aws_vpc_peering_connection_accepter.accepter` (line 22) and update the reference**

Change:
```hcl
resource "aws_vpc_peering_connection_accepter" "accepter" {
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
  auto_accept               = true
```

To:
```hcl
resource "aws_vpc_peering_connection_accepter" "accepter" {
  count    = var.connectivity_type == "peering" ? 1 : 0
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.owner[0].id
  auto_accept               = true
```

- [ ] **Step 3: Add `count` to `aws_route.owner` (line 39) and update the reference**

Change:
```hcl
resource "aws_route" "owner" {
  route_table_id            = module.eks_cluster_region_0.vpc_main_route_table_id
  destination_cidr_block    = local.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}
```

To:
```hcl
resource "aws_route" "owner" {
  count = var.connectivity_type == "peering" ? 1 : 0

  route_table_id            = module.eks_cluster_region_0.vpc_main_route_table_id
  destination_cidr_block    = local.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner[0].id
}
```

- [ ] **Step 4: Update `aws_route.owner_private` (line 45) count and reference**

Change:
```hcl
resource "aws_route" "owner_private" {
  count          = length(module.eks_cluster_region_0.private_route_table_ids)
  route_table_id = module.eks_cluster_region_0.private_route_table_ids[count.index]

  destination_cidr_block    = local.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}
```

To:
```hcl
resource "aws_route" "owner_private" {
  count          = var.connectivity_type == "peering" ? length(module.eks_cluster_region_0.private_route_table_ids) : 0
  route_table_id = module.eks_cluster_region_0.private_route_table_ids[count.index]

  destination_cidr_block    = local.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner[0].id
}
```

- [ ] **Step 5: Add `count` to `aws_route.accepter` (line 53) and update the reference**

Change:
```hcl
resource "aws_route" "accepter" {
  provider = aws.accepter

  route_table_id            = module.eks_cluster_region_1.vpc_main_route_table_id
  destination_cidr_block    = local.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}
```

To:
```hcl
resource "aws_route" "accepter" {
  count    = var.connectivity_type == "peering" ? 1 : 0
  provider = aws.accepter

  route_table_id            = module.eks_cluster_region_1.vpc_main_route_table_id
  destination_cidr_block    = local.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner[0].id
}
```

- [ ] **Step 6: Update `aws_route.accepter_private` (line 61) count and reference**

Change:
```hcl
resource "aws_route" "accepter_private" {
  provider = aws.accepter

  count          = length(module.eks_cluster_region_1.private_route_table_ids)
  route_table_id = module.eks_cluster_region_1.private_route_table_ids[count.index]

  destination_cidr_block    = local.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}
```

To:
```hcl
resource "aws_route" "accepter_private" {
  provider = aws.accepter

  count          = var.connectivity_type == "peering" ? length(module.eks_cluster_region_1.private_route_table_ids) : 0
  route_table_id = module.eks_cluster_region_1.private_route_table_ids[count.index]

  destination_cidr_block    = local.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner[0].id
}
```

- [ ] **Step 7: Add `count` to `aws_vpc_security_group_ingress_rule.owner_eks_primary` (line 76)**

Change:
```hcl
resource "aws_vpc_security_group_ingress_rule" "owner_eks_primary" {
  security_group_id = module.eks_cluster_region_0.cluster_primary_security_group_id

  cidr_ipv4   = local.accepter.vpc_cidr_block
```

To:
```hcl
resource "aws_vpc_security_group_ingress_rule" "owner_eks_primary" {
  count = var.connectivity_type == "peering" ? 1 : 0

  security_group_id = module.eks_cluster_region_0.cluster_primary_security_group_id

  cidr_ipv4   = local.accepter.vpc_cidr_block
```

- [ ] **Step 8: Add `count` to `aws_vpc_security_group_ingress_rule.accepter_eks_primary` (line 85)**

Change:
```hcl
resource "aws_vpc_security_group_ingress_rule" "accepter_eks_primary" {
  provider = aws.accepter

  security_group_id = module.eks_cluster_region_1.cluster_primary_security_group_id

  cidr_ipv4   = local.owner.vpc_cidr_block
```

To:
```hcl
resource "aws_vpc_security_group_ingress_rule" "accepter_eks_primary" {
  count    = var.connectivity_type == "peering" ? 1 : 0
  provider = aws.accepter

  security_group_id = module.eks_cluster_region_1.cluster_primary_security_group_id

  cidr_ipv4   = local.owner.vpc_cidr_block
```

- [ ] **Step 9: Format the file**

Run:
```bash
cd aws/kubernetes/eks-dual-region/terraform/clusters && terraform fmt vpc-peering.tf
```

- [ ] **Step 10: Commit**

```bash
git add aws/kubernetes/eks-dual-region/terraform/clusters/vpc-peering.tf
git commit -m "feat(dual-region): add count guards to vpc-peering resources"
```

---

### Task 3: Create `transit-gateway.tf`

**Files:**
- Create: `aws/kubernetes/eks-dual-region/terraform/clusters/transit-gateway.tf`

- [ ] **Step 1: Create the file with all TGW resources**

Create `aws/kubernetes/eks-dual-region/terraform/clusters/transit-gateway.tf`:

```hcl

################################
# Transit Gateway Attachment   #
################################
# These resources attach the two VPCs to an existing Transit Gateway.
# The Transit Gateway itself must be created outside this module.
# For cross-account TGW, provide the RAM share ARN.

locals {
  is_transit_gateway = var.connectivity_type == "transit-gateway"
  is_tgw_cross_account = local.is_transit_gateway && var.transit_gateway_ram_share_arn != null
}

################################
# Cross-Account RAM Share      #
################################

data "aws_caller_identity" "current" {
  count = local.is_tgw_cross_account ? 1 : 0
}

resource "aws_ram_principal_association" "tgw" {
  count = local.is_tgw_cross_account ? 1 : 0

  resource_share_arn = var.transit_gateway_ram_share_arn
  principal          = data.aws_caller_identity.current[0].account_id
}

################################
# VPC Attachments              #
################################

resource "aws_ec2_transit_gateway_vpc_attachment" "region_0" {
  count = local.is_transit_gateway ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = module.eks_cluster_region_0.vpc_id
  subnet_ids         = module.eks_cluster_region_0.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-${local.owner.region_full_name}-tgw-attachment"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "region_1" {
  count    = local.is_transit_gateway ? 1 : 0
  provider = aws.accepter

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = module.eks_cluster_region_1.vpc_id
  subnet_ids         = module.eks_cluster_region_1.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-${local.accepter.region_full_name}-tgw-attachment"
  }
}

################################
# Route Table Updates          #
################################
# These are required to let the VPC know where to route the traffic to.
# In this case non local cidr range --> Transit Gateway.

resource "aws_route" "owner_tgw" {
  count = local.is_transit_gateway ? 1 : 0

  route_table_id         = module.eks_cluster_region_0.vpc_main_route_table_id
  destination_cidr_block = local.accepter.vpc_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "owner_private_tgw" {
  count = local.is_transit_gateway ? length(module.eks_cluster_region_0.private_route_table_ids) : 0

  route_table_id         = module.eks_cluster_region_0.private_route_table_ids[count.index]
  destination_cidr_block = local.accepter.vpc_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "accepter_tgw" {
  count    = local.is_transit_gateway ? 1 : 0
  provider = aws.accepter

  route_table_id         = module.eks_cluster_region_1.vpc_main_route_table_id
  destination_cidr_block = local.owner.vpc_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "accepter_private_tgw" {
  count    = local.is_transit_gateway ? length(module.eks_cluster_region_1.private_route_table_ids) : 0
  provider = aws.accepter

  route_table_id         = module.eks_cluster_region_1.private_route_table_ids[count.index]
  destination_cidr_block = local.owner.vpc_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}

################################
# Security Groups Updates      #
################################
# These changes are required to actually allow inbound traffic from the other VPC.

resource "aws_vpc_security_group_ingress_rule" "owner_eks_primary_tgw" {
  count = local.is_transit_gateway ? 1 : 0

  security_group_id = module.eks_cluster_region_0.cluster_primary_security_group_id

  cidr_ipv4   = local.accepter.vpc_cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1
}

resource "aws_vpc_security_group_ingress_rule" "accepter_eks_primary_tgw" {
  count    = local.is_transit_gateway ? 1 : 0
  provider = aws.accepter

  security_group_id = module.eks_cluster_region_1.cluster_primary_security_group_id

  cidr_ipv4   = local.owner.vpc_cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1
}
```

- [ ] **Step 2: Format the file**

Run:
```bash
cd aws/kubernetes/eks-dual-region/terraform/clusters && terraform fmt transit-gateway.tf
```

- [ ] **Step 3: Validate syntax with terraform validate**

Run:
```bash
cd aws/kubernetes/eks-dual-region/terraform/clusters && terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

Note: `-backend=false` skips S3 backend config which requires credentials.

- [ ] **Step 4: Commit**

```bash
git add aws/kubernetes/eks-dual-region/terraform/clusters/transit-gateway.tf
git commit -m "feat(dual-region): add transit gateway connectivity option"
```

---

### Task 4: Add golden file test fixture for Transit Gateway

**Files:**
- Create: `aws/kubernetes/eks-dual-region/terraform/clusters/test/golden/golden-transit-gateway.tfvars`

- [ ] **Step 1: Create the TGW tfvars fixture**

Create `aws/kubernetes/eks-dual-region/terraform/clusters/test/golden/golden-transit-gateway.tfvars`:

```hcl
# use this file for vars without default values
# for the golden file generation with transit gateway connectivity

aws_profile        = null # uses default AWS credential chain (env vars, default profile, instance profile)
cluster_name       = "camunda"
connectivity_type  = "transit-gateway"
transit_gateway_id = "tgw-0123456789abcdef0"
```

- [ ] **Step 2: Commit**

```bash
git add aws/kubernetes/eks-dual-region/terraform/clusters/test/golden/golden-transit-gateway.tfvars
git commit -m "test(dual-region): add golden file fixture for transit gateway"
```

---

### Task 5: Update documentation

**Files:**
- Modify: `aws/kubernetes/eks-dual-region/README.md`
- Modify: `aws/kubernetes/eks-dual-region/DEVELOPER.md`

- [ ] **Step 1: Add connectivity type section to README.md**

After the existing content in `README.md`, add a section documenting the connectivity options:

```markdown

## Connectivity Options

By default, this reference architecture uses **VPC Peering** to connect the two regional VPCs. You can alternatively use an **AWS Transit Gateway** by setting the `connectivity_type` variable.

### VPC Peering (default)

No additional configuration needed. The peering connection is created and managed by Terraform.

### Transit Gateway

Requires a pre-existing Transit Gateway. Set the following variables:

```hcl
connectivity_type  = "transit-gateway"
transit_gateway_id = "tgw-0123456789abcdef0"  # your existing TGW ID
```

For cross-account Transit Gateway (e.g., in an enterprise landing zone with a shared networking account):

```hcl
connectivity_type            = "transit-gateway"
transit_gateway_id           = "tgw-0123456789abcdef0"
transit_gateway_ram_share_arn = "arn:aws:ram:eu-west-2:123456789012:resource-share/abc-123"
```
```

- [ ] **Step 2: Add connectivity note to DEVELOPER.md**

After step 3 in the "Cluster Setup" section of `DEVELOPER.md` (line 11, which mentions adjusting AWS regions), add:

```markdown
   - Optionally set `connectivity_type = "transit-gateway"` and `transit_gateway_id` in your `.tfvars` if testing with Transit Gateway instead of VPC Peering.
```

- [ ] **Step 3: Commit**

```bash
git add aws/kubernetes/eks-dual-region/README.md aws/kubernetes/eks-dual-region/DEVELOPER.md
git commit -m "docs(dual-region): document transit gateway connectivity option"
```
