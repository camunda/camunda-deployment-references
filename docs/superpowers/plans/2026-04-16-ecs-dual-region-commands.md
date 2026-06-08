# ECS Dual-Region Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create Claude Code commands and Terraform refactoring to guide users through deploying Camunda 8 on ECS Fargate across two AWS regions with configurable networking and secondary storage.

**Architecture:** Terraform variables replace hard-coded region/networking/storage config. Conditionals (`count`) toggle between Transit Gateway vs VPC Peering and RDBMS vs OpenSearch. Five Claude commands walk users through configure → deploy → verify → cleanup, persisting inputs as `terraform.tfvars`.

**Tech Stack:** Terraform (HCL), AWS (ECS Fargate, Aurora Global, OpenSearch, Transit Gateway, VPC Peering), Claude Code commands (Markdown)

**Spec:** `docs/superpowers/specs/2026-04-16-ecs-dual-region-commands-design.md`

---

### Task 1: Extract Region Variables from Hard-Coded Locals

**Files:**
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/variables.tf:1-16`
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/locals.tf`
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/config.tf:22-37`

- [ ] **Step 1: Replace hard-coded locals with variables in `variables.tf`**

Replace the `locals` block at lines 1-16 with proper variables:

```hcl
################################
# Region Configuration        #
################################

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

- [ ] **Step 2: Update `locals.tf` to derive from variables**

Replace the existing locals block content (keep `random_id` and computed values):

```hcl
################################
# Computed Values             #
################################

resource "random_id" "bucket_suffix" {
  byte_length = 3 # 6 hex characters
}

locals {
  prefix        = var.cluster_name
  bucket_suffix = random_id.bucket_suffix.hex

  # Region configuration (derived from variables)
  owner = {
    region         = var.region_0
    vpc_cidr_block = var.region_0_cidr
  }
  accepter = {
    region         = var.region_1
    vpc_cidr_block = var.region_1_cidr
  }

  # Truncate prefix for AWS resources with name length limits (e.g., ALB target groups: 32 chars)
  prefix_truncated = substr(local.prefix, 0, 14)

  # Region-specific prefixes
  prefix_region_0 = "${local.prefix}-r0"
  prefix_region_1 = "${local.prefix}-r1"

  # Zeebe dual-region cluster configuration
  # Even-numbered brokers (0, 2, 4, 6) in region 0
  # Odd-numbered brokers (1, 3, 5, 7) in region 1
  cluster_size       = 8
  replication_factor = 4
  partition_count    = 8
  brokers_per_region = 4
}
```

- [ ] **Step 3: Update `config.tf` providers to use variables**

Replace the provider blocks to reference variables directly instead of locals for the region (locals still used for tags):

```hcl
provider "aws" {
  region  = var.region_0
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  region  = var.region_1
  alias   = "accepter"
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}
```

- [ ] **Step 4: Run terraform validate**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add aws/containers/ecs-dual-region-fargate/terraform/clusters/variables.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/locals.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/config.tf
git commit -m "refactor: extract hard-coded regions to variables in ECS dual-region"
```

---

### Task 2: Add Networking Mode Variable and Conditional Transit Gateway

**Files:**
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/variables.tf`
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/transit-gateway.tf`

- [ ] **Step 1: Add `networking_mode` variable to `variables.tf`**

Add after the region variables block:

```hcl
################################################################
#                    Networking Options                         #
################################################################

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

- [ ] **Step 2: Wrap all `transit-gateway.tf` resources with count**

Add `count = var.networking_mode == "transit_gateway" ? 1 : 0` to the module and every resource. Update all cross-references to use `[0]` indexing:

```hcl
################################
# Transit Gateway             #
################################

module "transit_gateway" {
  count  = var.networking_mode == "transit_gateway" ? 1 : 0
  source = "../../../../modules/transit-gateway"

  providers = {
    aws.owner    = aws
    aws.accepter = aws.accepter
  }

  prefix = local.prefix
}

################################
# VPC Attachments             #
################################

# Attach region 0 VPC to region 0 TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "region_0" {
  count = var.networking_mode == "transit_gateway" ? 1 : 0

  transit_gateway_id = module.transit_gateway[0].owner_transit_gateway_id
  vpc_id             = module.vpc_region_0.vpc_id
  subnet_ids         = module.vpc_region_0.private_subnets

  dns_support = "enable"

  tags = {
    Name = "${local.prefix_region_0}-tgw-attachment"
  }
}

# Attach region 1 VPC to region 1 TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "region_1" {
  count    = var.networking_mode == "transit_gateway" ? 1 : 0
  provider = aws.accepter

  transit_gateway_id = module.transit_gateway[0].accepter_transit_gateway_id
  vpc_id             = module.vpc_region_1.vpc_id
  subnet_ids         = module.vpc_region_1.private_subnets

  dns_support = "enable"

  tags = {
    Name = "${local.prefix_region_1}-tgw-attachment"
  }
}

################################
# TGW Route Tables            #
################################

# Route from region 0 TGW to region 1 VPC CIDR via peering
resource "aws_ec2_transit_gateway_route" "region_0_to_region_1" {
  count = var.networking_mode == "transit_gateway" ? 1 : 0

  destination_cidr_block         = local.accepter.vpc_cidr_block
  transit_gateway_route_table_id = module.transit_gateway[0].owner_default_route_table_id
  transit_gateway_attachment_id  = module.transit_gateway[0].peering_attachment_id

  depends_on = [module.transit_gateway]
}

# Route from region 1 TGW to region 0 VPC CIDR via peering
resource "aws_ec2_transit_gateway_route" "region_1_to_region_0" {
  count    = var.networking_mode == "transit_gateway" ? 1 : 0
  provider = aws.accepter

  destination_cidr_block         = local.owner.vpc_cidr_block
  transit_gateway_route_table_id = module.transit_gateway[0].accepter_default_route_table_id
  transit_gateway_attachment_id  = module.transit_gateway[0].peering_accepter_attachment_id
}

################################
# VPC Route Tables            #
################################

# Region 0: route to region 1 CIDR via TGW
resource "aws_route" "region_0_private_to_region_1_tgw" {
  count = var.networking_mode == "transit_gateway" ? length(module.vpc_region_0.private_route_table_ids) : 0

  route_table_id         = module.vpc_region_0.private_route_table_ids[count.index]
  destination_cidr_block = local.accepter.vpc_cidr_block
  transit_gateway_id     = module.transit_gateway[0].owner_transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.region_0]
}

# Region 1: route to region 0 CIDR via TGW
resource "aws_route" "region_1_private_to_region_0_tgw" {
  count    = var.networking_mode == "transit_gateway" ? length(module.vpc_region_1.private_route_table_ids) : 0
  provider = aws.accepter

  route_table_id         = module.vpc_region_1.private_route_table_ids[count.index]
  destination_cidr_block = local.owner.vpc_cidr_block
  transit_gateway_id     = module.transit_gateway[0].accepter_transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.region_1]
}
```

Note: The VPC route resources are renamed from `region_0_private_to_region_1` to `region_0_private_to_region_1_tgw` to avoid name collisions with the VPC peering routes. This requires a `terraform state mv` or fresh deploy.

- [ ] **Step 3: Run terraform validate**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add aws/containers/ecs-dual-region-fargate/terraform/clusters/variables.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/transit-gateway.tf
git commit -m "refactor: make Transit Gateway conditional via networking_mode variable"
```

---

### Task 3: Add VPC Peering Alternative

**Files:**
- Create: `aws/containers/ecs-dual-region-fargate/terraform/clusters/vpc-peering.tf`

- [ ] **Step 1: Create `vpc-peering.tf`**

```hcl
################################################################
#               VPC Peering (alternative to Transit Gateway)    #
################################################################

# Requester (region 0) creates the peering connection
resource "aws_vpc_peering_connection" "cross_region" {
  count = var.networking_mode == "vpc_peering" ? 1 : 0

  vpc_id      = module.vpc_region_0.vpc_id
  peer_vpc_id = module.vpc_region_1.vpc_id
  peer_region = var.region_1
  auto_accept = false

  tags = {
    Name = "${local.prefix}-vpc-peering"
  }
}

# Accepter (region 1) accepts the peering connection
resource "aws_vpc_peering_connection_accepter" "cross_region" {
  count    = var.networking_mode == "vpc_peering" ? 1 : 0
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id
  auto_accept               = true

  tags = {
    Name = "${local.prefix}-vpc-peering"
  }
}

# Enable DNS resolution on requester side
resource "aws_vpc_peering_connection_options" "requester" {
  count = var.networking_mode == "vpc_peering" ? 1 : 0

  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.cross_region]
}

# Enable DNS resolution on accepter side
resource "aws_vpc_peering_connection_options" "accepter" {
  count    = var.networking_mode == "vpc_peering" ? 1 : 0
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.cross_region]
}

################################
# VPC Route Tables (Peering)  #
################################

# Region 0: route to region 1 CIDR via peering
resource "aws_route" "region_0_private_to_region_1_peering" {
  count = var.networking_mode == "vpc_peering" ? length(module.vpc_region_0.private_route_table_ids) : 0

  route_table_id            = module.vpc_region_0.private_route_table_ids[count.index]
  destination_cidr_block    = local.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id
}

# Region 1: route to region 0 CIDR via peering
resource "aws_route" "region_1_private_to_region_0_peering" {
  count    = var.networking_mode == "vpc_peering" ? length(module.vpc_region_1.private_route_table_ids) : 0
  provider = aws.accepter

  route_table_id            = module.vpc_region_1.private_route_table_ids[count.index]
  destination_cidr_block    = local.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id
}
```

- [ ] **Step 2: Run terraform validate**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add aws/containers/ecs-dual-region-fargate/terraform/clusters/vpc-peering.tf
git commit -m "feat: add VPC Peering as alternative networking mode"
```

---

### Task 4: Add Secondary Storage Type Variable and Conditional Aurora/OpenSearch

**Files:**
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/variables.tf`
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/aurora-global.tf`
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/postgres_seed.tf`
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/outputs.tf`
- Create: `aws/containers/ecs-dual-region-fargate/terraform/clusters/opensearch.tf`

- [ ] **Step 1: Add `secondary_storage_type` variable to `variables.tf`**

Add after the networking options block:

```hcl
################################################################
#                   Secondary Storage Options                   #
################################################################

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

- [ ] **Step 2: Wrap `aurora-global.tf` with count**

```hcl
################################################################
#                 Aurora Global Database                        #
################################################################

module "aurora_global" {
  count  = var.secondary_storage_type == "rdbms" ? 1 : 0
  source = "../../../../modules/aurora-global"

  providers = {
    aws.primary   = aws
    aws.secondary = aws.accepter
  }

  global_cluster_identifier = "${local.prefix}-global-db"

  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  engine_version             = "17.9"
  auto_minor_version_upgrade = false
  database_name              = var.db_name

  master_username  = var.db_admin_username
  master_password  = local.db_admin_password_effective
  iam_auth_enabled = var.db_iam_auth_enabled

  # Primary cluster (region 0 — writer)
  primary_cluster_name       = "${local.prefix_region_0}-camunda-db"
  primary_vpc_id             = module.vpc_region_0.vpc_id
  primary_subnet_ids         = module.vpc_region_0.private_subnets
  primary_cidr_blocks        = [local.owner.vpc_cidr_block, local.accepter.vpc_cidr_block]
  primary_availability_zones = module.vpc_region_0.azs
  primary_num_instances      = 1

  # Secondary cluster (region 1 — read replicas)
  secondary_cluster_name  = "${local.prefix_region_1}-camunda-db"
  secondary_vpc_id        = module.vpc_region_1.vpc_id
  secondary_subnet_ids    = module.vpc_region_1.private_subnets
  secondary_cidr_blocks   = [local.owner.vpc_cidr_block, local.accepter.vpc_cidr_block]
  secondary_num_instances = 1
}
```

- [ ] **Step 3: Wrap `postgres_seed.tf` resources with count**

The seed task should only run for RDBMS. Update both the log group and task definition resources by changing:

- `count = var.db_seed_enabled ? 1 : 0` → `count = var.secondary_storage_type == "rdbms" && var.db_seed_enabled ? 1 : 0`

Apply this to `aws_cloudwatch_log_group.db_seed`, `aws_ecs_task_definition.db_seed`, and `null_resource.run_db_seed_task`.

Also update the `depends_on` in `null_resource.run_db_seed_task`:

```hcl
  depends_on = [
    module.aurora_global,
    aws_ecs_cluster.region_0,
    aws_ecs_task_definition.db_seed,
  ]
```

- [ ] **Step 4: Create `opensearch.tf`**

```hcl
################################################################
#           OpenSearch (alternative to Aurora Global)           #
################################################################

module "opensearch_region_0" {
  count  = var.secondary_storage_type == "opensearch" ? 1 : 0
  source = "../../../../modules/opensearch"

  domain_name = "${local.prefix_region_0}-opensearch"
  vpc_id      = module.vpc_region_0.vpc_id
  subnet_ids  = [module.vpc_region_0.private_subnets[0]]
  cidr_blocks = [local.owner.vpc_cidr_block, local.accepter.vpc_cidr_block]

  instance_type  = "t3.medium.search"
  instance_count = 1

  advanced_security_enabled     = true
  advanced_security_internal_db = true
  advanced_security_master_user = var.db_admin_username
  advanced_security_master_pass = local.db_admin_password_effective

  tags = {
    Name = "${local.prefix_region_0}-opensearch"
  }
}

module "opensearch_region_1" {
  count  = var.secondary_storage_type == "opensearch" ? 1 : 0
  source = "../../../../modules/opensearch"

  providers = {
    aws = aws.accepter
  }

  domain_name = "${local.prefix_region_1}-opensearch"
  vpc_id      = module.vpc_region_1.vpc_id
  subnet_ids  = [module.vpc_region_1.private_subnets[0]]
  cidr_blocks = [local.owner.vpc_cidr_block, local.accepter.vpc_cidr_block]

  instance_type  = "t3.medium.search"
  instance_count = 1

  advanced_security_enabled     = true
  advanced_security_internal_db = true
  advanced_security_master_user = var.db_admin_username
  advanced_security_master_pass = local.db_admin_password_effective

  tags = {
    Name = "${local.prefix_region_1}-opensearch"
  }
}
```

- [ ] **Step 5: Update Aurora outputs to be conditional**

In `outputs.tf`, wrap Aurora-specific outputs with a condition. Replace the Aurora outputs section:

```hcl
################################################################
#                        Aurora Outputs                        #
################################################################

output "aurora_global_cluster_id" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].global_cluster_id : null
  description = "The ID of the Aurora Global Database cluster"
}

output "aurora_primary_endpoint" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].primary_cluster_endpoint : null
  description = "The writer endpoint of the Aurora Global DB primary cluster (region 0)"
}

output "aurora_secondary_endpoint" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].secondary_cluster_endpoint : null
  description = "The endpoint of the Aurora Global DB secondary cluster (region 1)"
}

output "aurora_primary_cluster_identifier" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].primary_cluster_identifier : null
  description = "The cluster identifier of the Aurora primary cluster (region 0)"
}

output "aurora_secondary_cluster_identifier" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].secondary_cluster_identifier : null
  description = "The cluster identifier of the Aurora secondary cluster (region 1)"
}

################################################################
#                     OpenSearch Outputs                        #
################################################################

output "opensearch_region_0_endpoint" {
  value       = var.secondary_storage_type == "opensearch" ? module.opensearch_region_0[0].domain_endpoint : null
  description = "The endpoint of the OpenSearch domain in region 0"
}

output "opensearch_region_1_endpoint" {
  value       = var.secondary_storage_type == "opensearch" ? module.opensearch_region_1[0].domain_endpoint : null
  description = "The endpoint of the OpenSearch domain in region 1"
}
```

- [ ] **Step 6: Run terraform validate**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 7: Commit**

```bash
git add aws/containers/ecs-dual-region-fargate/terraform/clusters/variables.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/aurora-global.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/postgres_seed.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/opensearch.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/outputs.tf
git commit -m "feat: add secondary_storage_type variable with OpenSearch alternative"
```

---

### Task 5: Update `camunda.tf` Environment Variables for Storage Type Conditionals

**Files:**
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/camunda.tf`
- Modify: `aws/containers/ecs-dual-region-fargate/terraform/clusters/locals.tf`

- [ ] **Step 1: Add storage-specific locals to `locals.tf`**

Add at the end of the locals block:

```hcl
  # Secondary storage environment variables (conditional on storage type)
  rdbms_env_vars = [
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_AUTOCONFIGURECAMUNDAEXPORTER"
      value = "false"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "rdbms"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_URL"
      value = "jdbc:aws-wrapper:postgresql://${var.secondary_storage_type == "rdbms" ? module.aurora_global[0].primary_cluster_endpoint : "unused"}:5432/${var.db_name}?wrapperPlugins=iam,failover"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_USERNAME"
      value = "camunda"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_AUTODDL"
      value = "true"
    },
    {
      name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
      value = "software.amazon.jdbc.Driver"
    },
  ]

  opensearch_env_vars_region_0 = [
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "opensearch"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_URL"
      value = "https://${var.secondary_storage_type == "opensearch" ? module.opensearch_region_0[0].domain_endpoint : "unused"}"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_USERNAME"
      value = var.db_admin_username
    },
  ]

  opensearch_env_vars_region_1 = [
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "opensearch"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_URL"
      value = "https://${var.secondary_storage_type == "opensearch" ? module.opensearch_region_1[0].domain_endpoint : "unused"}"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_USERNAME"
      value = var.db_admin_username
    },
  ]

  # Common env vars shared by both storage types (admin, connectors, backup)
  common_env_vars = [
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_USERNAME"
      value = "admin"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_NAME"
      value = "Admin User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_EMAIL"
      value = "admin@example.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0"
      value = "admin"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_USERNAME"
      value = "connectors"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_NAME"
      value = "Connectors User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_EMAIL"
      value = "connectors@example.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_USERS_0"
      value = "connectors"
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_STORE"
      value = "S3"
    },
  ]
```

- [ ] **Step 2: Update `camunda.tf` orchestration modules to use conditional env vars**

Replace the `environment_variables` block in both `orchestration_cluster_region_0` and `orchestration_cluster_region_1` modules:

For region 0:
```hcl
  environment_variables = concat(
    var.secondary_storage_type == "rdbms" ? local.rdbms_env_vars : local.opensearch_env_vars_region_0,
    local.common_env_vars,
    [
      {
        name  = "CAMUNDA_DATA_BACKUP_S3_BUCKETNAME"
        value = aws_s3_bucket.backup_region_0.bucket
      },
      {
        name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
        value = aws_s3_bucket.backup_region_0.bucket
      },
    ]
  )
```

For region 1:
```hcl
  environment_variables = concat(
    var.secondary_storage_type == "rdbms" ? local.rdbms_env_vars : local.opensearch_env_vars_region_1,
    local.common_env_vars,
    [
      {
        name  = "CAMUNDA_DATA_BACKUP_S3_BUCKETNAME"
        value = aws_s3_bucket.backup_region_1.bucket
      },
      {
        name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
        value = aws_s3_bucket.backup_region_1.bucket
      },
    ]
  )
```

Also update `depends_on` in both orchestration modules to be conditional:

```hcl
  depends_on = var.secondary_storage_type == "rdbms" ? [null_resource.run_db_seed_task] : []
```

Note: Terraform doesn't support conditional `depends_on`. Instead, remove the `depends_on` from the module blocks entirely — the dependency is implicit through the environment variables referencing `module.aurora_global[0]`.

- [ ] **Step 3: Update IAM policies to be conditional for RDBMS**

In `iam.tf`, the `rds_db_connect_region_0` and `rds_db_connect_region_1` policies should only be created for RDBMS:

```hcl
resource "aws_iam_policy" "rds_db_connect_region_0" {
  count = var.secondary_storage_type == "rdbms" ? 1 : 0
  # ... rest of resource unchanged
}

resource "aws_iam_policy" "rds_db_connect_region_1" {
  count    = var.secondary_storage_type == "rdbms" ? 1 : 0
  provider = aws.accepter
  # ... rest of resource unchanged
}
```

Update `extra_task_role_attachments` in `camunda.tf` to conditionally include RDS policy:

For region 0:
```hcl
  extra_task_role_attachments = compact([
    var.secondary_storage_type == "rdbms" ? aws_iam_policy.rds_db_connect_region_0[0].arn : "",
    aws_iam_policy.s3_backup_access_region_0.arn,
  ])
```

For region 1:
```hcl
  extra_task_role_attachments = compact([
    var.secondary_storage_type == "rdbms" ? aws_iam_policy.rds_db_connect_region_1[0].arn : "",
    aws_iam_policy.s3_backup_access_region_1.arn,
  ])
```

- [ ] **Step 4: Run terraform validate**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add aws/containers/ecs-dual-region-fargate/terraform/clusters/camunda.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/locals.tf \
        aws/containers/ecs-dual-region-fargate/terraform/clusters/iam.tf
git commit -m "feat: conditional environment variables based on secondary_storage_type"
```

---

### Task 6: Create Command 1 — Configure

**Files:**
- Create: `.claude/commands/ecs-dual-region/1-configure.md`

- [ ] **Step 1: Create the configure command**

```markdown
# Configure ECS Dual-Region Deployment (Step 1/5)

Set up the deployment configuration by collecting inputs and writing `terraform.tfvars`.

## Camunda Context

Camunda 8 runs on ECS Fargate with Zeebe brokers distributed across two AWS regions. This provides:
- **High availability:** If one region fails, the other has a full copy of all data
- **8 brokers** with replication factor 4 ensures every partition exists in both regions
- **Connectors** handle external system integration (REST, messaging), one per region

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

Check if `aws/containers/ecs-dual-region-fargate/terraform/clusters/terraform.tfvars` already exists.
- If yes: read it, show current values, and ask which to change.
- If no: collect all inputs fresh.

### Inputs to Collect

Ask these questions **one at a time**, showing the default value. Only write non-default values to tfvars.

1. **Cluster name** (required, no default): Prefix for all AWS resources. Must be lowercase, alphanumeric + hyphens, max 20 chars.

2. **AWS profile** (default: null — uses default credential chain): Which AWS credential profile to use.

3. **Region 0** (default: `eu-west-2` — London): Primary region with Aurora writer and Zeebe brokers 0,2,4,6.

4. **Region 1** (default: `eu-west-3` — Paris): Secondary region with Aurora read replicas and Zeebe brokers 1,3,5,7.

5. **VPC CIDR for region 0** (default: `10.192.0.0/16`): Must not overlap with region 1 CIDR.

6. **VPC CIDR for region 1** (default: `10.202.0.0/16`): Must not overlap with region 0 CIDR.

7. **Networking mode** (default: `transit_gateway`):
   - **Transit Gateway** — Scalable hub, supports future multi-VPC topologies. ~$0.05/GB + hourly charge. Best for production.
   - **VPC Peering** — Simpler, no per-GB data transfer cost, direct 1:1 connection. Best for dev/testing.

8. **Secondary storage** (default: `rdbms`):
   - **RDBMS (Aurora Global)** — Simpler, cheaper, built-in cross-region replication and failover. Supports all Camunda components except Optimize.
   - **OpenSearch** — Required if you need Optimize (process analytics). One independent domain per region, brokers export to both.

9. **Restrict load balancer access** (default: `0.0.0.0/0`): CIDR blocks allowed to reach ALB/NLB. Comma-separated for multiple.

10. **S3 force destroy** (default: `true` for dev): Allow terraform destroy to remove non-empty backup buckets.

11. **Single NAT gateway** (default: `true` for cost savings): Use one NAT gateway per region instead of one per AZ. Not recommended for production HA.

### Write tfvars

After collecting all inputs, generate the tfvars content and show it to the user for review before writing.

Example output:
```hcl
# terraform.tfvars — generated by /ecs-dual-region/1-configure
cluster_name         = "my-test"
aws_profile          = "default"
networking_mode      = "vpc_peering"
secondary_storage_type = "rdbms"
s3_force_destroy     = true
single_nat_gateway   = true
limit_access_to_cidrs = ["10.0.0.0/8"]
```

Write to: `aws/containers/ecs-dual-region-fargate/terraform/clusters/terraform.tfvars`

## Success

Tell the user: "Configuration saved. Proceed with `/ecs-dual-region/2-deploy-infra`"
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/ecs-dual-region/1-configure.md
git commit -m "feat: add ECS dual-region configure command"
```

---

### Task 7: Create Command 2 — Deploy Infrastructure

**Files:**
- Create: `.claude/commands/ecs-dual-region/2-deploy-infra.md`

- [ ] **Step 1: Create the deploy-infra command**

```markdown
# Deploy ECS Dual-Region Infrastructure (Step 2/5)

Deploy all infrastructure via Terraform: VPCs, cross-region networking, database/search, ECS clusters, load balancers.

## Pre-Checks

1. Verify tfvars exists and read the configuration:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/clusters/terraform.tfvars
```
If missing, tell the user to run `/ecs-dual-region/1-configure` first.

2. Extract `aws_profile` from tfvars for CLI commands. If set, use `--profile <value>` on all AWS CLI commands. If null/empty, omit the flag.

## Camunda Context

This creates the full infrastructure for dual-region Camunda 8:
- **2 VPCs** with private/public subnets across 3 AZs each
- **Cross-region networking** (Transit Gateway or VPC Peering) for Raft consensus traffic
- **Aurora Global Database** (if RDBMS) or **OpenSearch domains** (if OpenSearch) for secondary storage
- **ECS clusters** with Fargate capacity providers in both regions
- **Load balancers:** ALB (HTTP port 8080, management 9600), NLB external (gRPC 26500), NLB internal (Raft 26502)
- **IAM roles, KMS keys, S3 backup buckets, Secrets Manager**

## Steps

1. **Initialize Terraform:**
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters
terraform init
```
If using S3 backend, provide the backend config. For local state, just run `terraform init`.

2. **Plan the deployment:**
```bash
terraform plan
```
Show the user a summary of resources to be created. Ask them to confirm before proceeding.

3. **Apply:**
```bash
terraform apply -auto-approve
```
This takes 15-25 minutes (Aurora Global DB creation is the bottleneck).

4. **Show key outputs:**
```bash
terraform output
```

Present the outputs in a readable format, highlighting:
- Region 0 ALB endpoint (Camunda web UI)
- Region 1 ALB endpoint (Camunda web UI)
- Region 0/1 gRPC NLB endpoints (Zeebe client access)
- Aurora endpoints (if RDBMS)
- OpenSearch endpoints (if OpenSearch)

5. **Provide export block** for the user to copy-paste into their shell:
```bash
export CLUSTER_NAME="<from tfvars>"
export REGION_0="<from terraform output>"
export REGION_1="<from terraform output>"
export ALB_ENDPOINT_0="<from terraform output>"
export ALB_ENDPOINT_1="<from terraform output>"
```

## Troubleshooting

- **Aurora creation timeout:** Aurora Global DB can take 15+ minutes. If Terraform times out, run `terraform apply` again — it will pick up where it left off.
- **Insufficient capacity:** Some regions have limited Fargate capacity. Try a different AZ or region.
- **Permission errors:** Ensure your AWS credentials have admin-level access or the specific permissions for ECS, RDS, EC2, ELB, IAM, KMS, S3, CloudWatch, and Route 53.

## Success

Tell the user: "Infrastructure deployed. Proceed with `/ecs-dual-region/3-deploy-camunda`"
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/ecs-dual-region/2-deploy-infra.md
git commit -m "feat: add ECS dual-region deploy-infra command"
```

---

### Task 8: Create Command 3 — Deploy Camunda

**Files:**
- Create: `.claude/commands/ecs-dual-region/3-deploy-camunda.md`

- [ ] **Step 1: Create the deploy-camunda command**

```markdown
# Deploy Camunda on ECS Dual-Region (Step 3/5)

Monitor ECS services reaching steady state and Zeebe Raft quorum formation.

## Pre-Checks

1. Read `aws_profile` and `cluster_name` from tfvars:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/clusters/terraform.tfvars
```

2. Verify ECS clusters exist:
```bash
aws ecs describe-clusters --clusters <cluster_name>-r0-cluster --region <region_0> [--profile <profile>]
aws ecs describe-clusters --clusters <cluster_name>-r1-cluster --region <region_1> [--profile <profile>]
```
Both should return `ACTIVE` status. If not, run `/ecs-dual-region/2-deploy-infra` first.

## Camunda Context

Terraform already created the ECS services and task definitions. This step monitors their startup:
- **4 Zeebe brokers per region** (8 total) participate in Raft consensus across regions
- **Raft quorum formation takes ~20 minutes** because brokers must discover each other cross-region via NLB
- **Replication factor 4** means every partition has copies in both regions — if one region goes down, the other has complete data
- **Connectors** (1 per region) start faster since they just connect to the local Zeebe gateway

## Steps

1. **Monitor orchestration cluster services:**
```bash
aws ecs describe-services \
  --cluster <cluster_name>-r0-cluster \
  --services <cluster_name>-r0-oc-service \
  --region <region_0> [--profile <profile>] \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'

aws ecs describe-services \
  --cluster <cluster_name>-r1-cluster \
  --services <cluster_name>-r1-oc-service \
  --region <region_1> [--profile <profile>] \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'
```
Wait until `running` equals `desired` (4) in both regions.

2. **Monitor connectors services:**
```bash
aws ecs describe-services \
  --cluster <cluster_name>-r0-cluster \
  --services <cluster_name>-r0-oc-connectors-service \
  --region <region_0> [--profile <profile>] \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'

aws ecs describe-services \
  --cluster <cluster_name>-r1-cluster \
  --services <cluster_name>-r1-oc-connectors-service \
  --region <region_1> [--profile <profile>] \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'
```
Wait until `running` equals `desired` (1) in both regions.

3. **Wait for Raft quorum (~20 minutes):**

Poll the Zeebe topology endpoint via ALB. Get the ALB endpoint from terraform output:
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters
ALB_R0=$(terraform output -raw region_0_alb_endpoint)
```

Then poll:
```bash
curl -s "http://${ALB_R0}:8080/v2/topology" | jq '.brokers | length'
```
Wait until this returns `8` (all brokers registered).

4. **Verify partition leaders:**
```bash
curl -s "http://${ALB_R0}:8080/v2/topology" | jq '.brokers[].partitions[] | select(.role == "LEADER")' | jq -s 'length'
```
Should return `8` (one leader per partition).

## Troubleshooting

- **Tasks keep stopping:** Check CloudWatch logs:
  ```bash
  LOG_GROUP=$(terraform output -raw region_0_log_group_name)
  aws logs tail "$LOG_GROUP" --since 10m --region <region_0> [--profile <profile>]
  ```
- **Raft doesn't form:** Verify cross-region NLB is reachable. Check security groups allow port 26502 between VPC CIDRs.
- **Aurora connection fails:** Verify the DB seed task succeeded. Check CloudWatch log group `/ecs/<cluster_name>-r0-db-seed`.
- **Only some brokers register:** Some brokers may take longer. Wait up to 25 minutes before investigating.

## Success

Tell the user: "Camunda is running. Proceed with `/ecs-dual-region/4-verify`"
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/ecs-dual-region/3-deploy-camunda.md
git commit -m "feat: add ECS dual-region deploy-camunda command"
```

---

### Task 9: Create Command 4 — Verify

**Files:**
- Create: `.claude/commands/ecs-dual-region/4-verify.md`

- [ ] **Step 1: Create the verify command**

```markdown
# Verify ECS Dual-Region Deployment (Step 4/5)

Comprehensive health check of the dual-region Camunda deployment.

## Pre-Checks

Read `aws_profile`, `cluster_name`, `secondary_storage_type` from tfvars:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/clusters/terraform.tfvars
```

Get endpoints from terraform output:
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters
terraform output
```

## Camunda Context

A healthy dual-region deployment has: 8 brokers, 8 partitions, each partition with 4 replicas spread across both regions, and every partition with exactly one leader.

## Checks

Run all checks and report results as PASS/FAIL/WARN.

### 1. ECS Service Status

```bash
# Region 0 orchestration (expect 4 running)
aws ecs describe-services \
  --cluster <cluster_name>-r0-cluster \
  --services <cluster_name>-r0-oc-service \
  --region <region_0> [--profile <profile>] \
  --query 'services[0].runningCount'

# Region 1 orchestration (expect 4 running)
aws ecs describe-services \
  --cluster <cluster_name>-r1-cluster \
  --services <cluster_name>-r1-oc-service \
  --region <region_1> [--profile <profile>] \
  --query 'services[0].runningCount'

# Region 0 connectors (expect 1 running)
aws ecs describe-services \
  --cluster <cluster_name>-r0-cluster \
  --services <cluster_name>-r0-oc-connectors-service \
  --region <region_0> [--profile <profile>] \
  --query 'services[0].runningCount'

# Region 1 connectors (expect 1 running)
aws ecs describe-services \
  --cluster <cluster_name>-r1-cluster \
  --services <cluster_name>-r1-oc-connectors-service \
  --region <region_1> [--profile <profile>] \
  --query 'services[0].runningCount'
```

PASS: 4+4 orchestration, 1+1 connectors running.

### 2. Zeebe Topology

```bash
ALB_R0=$(terraform output -raw region_0_alb_endpoint)
curl -s "http://${ALB_R0}:8080/v2/topology"
```

Check:
- `brokers` array has 8 entries: PASS/FAIL
- Each partition (1-8) has exactly one LEADER: PASS/FAIL
- Each partition has 4 replicas total: PASS/FAIL

### 3. Cross-Region Connectivity

```bash
ALB_R1=$(terraform output -raw region_1_alb_endpoint)

# Both ALBs respond
curl -sf "http://${ALB_R0}:8080/v2/topology" > /dev/null && echo "Region 0 ALB: PASS" || echo "Region 0 ALB: FAIL"
curl -sf "http://${ALB_R1}:8080/v2/topology" > /dev/null && echo "Region 1 ALB: PASS" || echo "Region 1 ALB: FAIL"
```

### 4. Secondary Storage Health

**If RDBMS (Aurora Global):**
```bash
AURORA_ID=$(terraform output -raw aurora_primary_cluster_identifier)
aws rds describe-global-clusters \
  --global-cluster-identifier $(terraform output -raw aurora_global_cluster_id) \
  [--profile <profile>] \
  --query 'GlobalClusters[0].{Status:Status,Members:GlobalClusterMembers[*].{Identifier:DBClusterIdentifier,IsWriter:IsClusterWriter}}'
```
PASS: Status is "available", one writer + one reader member.

**If OpenSearch:**
```bash
OS_R0=$(terraform output -raw opensearch_region_0_endpoint)
curl -sf "https://${OS_R0}/_cluster/health" -u "<admin_user>:<admin_pass>" | jq '.status'
```
PASS: Status is "green" in both regions.

### 5. Optional Workflow Test

Deploy a simple process and verify it completes:
```bash
# Create a process instance via REST API
curl -X POST "http://${ALB_R0}:8080/v2/process-instances" \
  -H "Content-Type: application/json" \
  -u "admin:<password>" \
  -d '{"bpmnProcessId": "test-process"}'
```

Note: This requires deploying a test process first. Skip if no process is deployed.

## Summary

Present results as a table:

| Check | Expected | Result |
|-------|----------|--------|
| Region 0 orchestration tasks | 4 running | ? |
| Region 1 orchestration tasks | 4 running | ? |
| Region 0 connectors tasks | 1 running | ? |
| Region 1 connectors tasks | 1 running | ? |
| Zeebe brokers | 8 total | ? |
| Partition leaders | 8 leaders | ? |
| Region 0 ALB | Reachable | ? |
| Region 1 ALB | Reachable | ? |
| Secondary storage | Available | ? |

## Success

Tell the user: "Deployment verified. To tear down, run `/ecs-dual-region/5-cleanup`"
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/ecs-dual-region/4-verify.md
git commit -m "feat: add ECS dual-region verify command"
```

---

### Task 10: Create Command 5 — Cleanup

**Files:**
- Create: `.claude/commands/ecs-dual-region/5-cleanup.md`

- [ ] **Step 1: Create the cleanup command**

```markdown
# Cleanup ECS Dual-Region Deployment (Step 5/5)

Destroy all resources created by the ECS dual-region deployment.

## Pre-Checks

1. Read `aws_profile` and `cluster_name` from tfvars:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/clusters/terraform.tfvars
```

2. **Confirm with user:** "This will destroy ALL resources including ECS clusters, databases, load balancers, and S3 buckets. This action cannot be undone. Proceed? (yes/no)"

Do NOT proceed without explicit user confirmation.

## Steps

1. **Scale ECS services to 0 (graceful shutdown):**

```bash
# Region 0
aws ecs update-service \
  --cluster <cluster_name>-r0-cluster \
  --service <cluster_name>-r0-oc-service \
  --desired-count 0 \
  --region <region_0> [--profile <profile>]

aws ecs update-service \
  --cluster <cluster_name>-r0-cluster \
  --service <cluster_name>-r0-oc-connectors-service \
  --desired-count 0 \
  --region <region_0> [--profile <profile>]

# Region 1
aws ecs update-service \
  --cluster <cluster_name>-r1-cluster \
  --service <cluster_name>-r1-oc-service \
  --desired-count 0 \
  --region <region_1> [--profile <profile>]

aws ecs update-service \
  --cluster <cluster_name>-r1-cluster \
  --service <cluster_name>-r1-oc-connectors-service \
  --desired-count 0 \
  --region <region_1> [--profile <profile>]
```

2. **Wait for tasks to drain** (1-2 minutes):
```bash
aws ecs wait services-stable \
  --cluster <cluster_name>-r0-cluster \
  --services <cluster_name>-r0-oc-service \
  --region <region_0> [--profile <profile>]
```

3. **Run terraform destroy:**
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters
terraform destroy
```
Show the plan and confirm with the user before typing "yes".

This takes 10-20 minutes (Aurora Global DB deletion is the bottleneck).

4. **Verify no orphaned resources:**

If terraform destroy fails on VPC deletion, it's usually orphaned ENIs from ECS/Lambda:

```bash
# Check for orphaned ENIs in region 0
VPC_R0=$(terraform output -raw 2>/dev/null || echo "check-state")
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=<vpc_id>" \
  --region <region_0> [--profile <profile>] \
  --query 'NetworkInterfaces[*].{Id:NetworkInterfaceId,Status:Status,Description:Description}'
```

If orphaned ENIs exist:
- Wait 5 minutes (Lambda ENIs auto-cleanup)
- If still present, manually detach and delete:
  ```bash
  aws ec2 delete-network-interface --network-interface-id <eni-id> --region <region_0> [--profile <profile>]
  ```
- Then retry `terraform destroy`

## Success

Tell the user: "All resources destroyed."
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/ecs-dual-region/5-cleanup.md
git commit -m "feat: add ECS dual-region cleanup command"
```

---

### Task 11: Run terraform fmt and Final Validation

**Files:**
- All `.tf` files in `aws/containers/ecs-dual-region-fargate/terraform/clusters/`

- [ ] **Step 1: Format all Terraform files**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters && terraform fmt
```

- [ ] **Step 2: Validate with default values (RDBMS + Transit Gateway)**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit any formatting changes**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/clusters
git add *.tf
git diff --cached --quiet || git commit -m "style: terraform fmt"
```
