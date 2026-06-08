# Deploy ECS Dual-Region Infrastructure (Step 2/5)

Deploy the **infra** layer: VPCs, cross-region networking, Aurora Global / OpenSearch, ECS clusters, load balancers, KMS, S3, secrets, IAM. The Camunda app layer comes in step 3.

## Pre-Checks

1. Verify infra tfvars exists and read the configuration:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/infra/terraform.tfvars
```
If missing, tell the user to run `/ecs-dual-region/1-configure` first.

2. Extract `aws_profile` from tfvars for CLI commands. If set, use `--profile <value>` on all AWS CLI commands. If null/empty, omit the flag.

## Camunda Context

This step deploys everything *except* the Camunda task definitions:
- **2 VPCs** with private/public subnets across 3 AZs each
- **Cross-region networking** (Transit Gateway or VPC Peering) for Raft consensus traffic
- **Aurora Global Database** (if RDBMS) or **OpenSearch domains** (if OpenSearch) for secondary storage
- **ECS clusters** with Fargate capacity providers in both regions (no services yet)
- **Load balancers:** ALB (HTTP on port 80 → container 8080, management 9600), NLB external (gRPC 26500), NLB internal (Raft 26502)
- **IAM roles, KMS keys, S3 backup buckets, Secrets Manager, Route 53 Resolver**

## Steps

1. **Initialize Terraform (infra state):**
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/infra
terraform init
```
If using S3 backend, pass `-backend-config=...`. Otherwise local state is fine for dev.

2. **Plan:**
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
- `region_0_alb_endpoint` / `region_1_alb_endpoint` (Camunda HTTP, port 80)
- `region_0_nlb_grpc_endpoint` / `region_1_nlb_grpc_endpoint` (Zeebe gRPC, port 26500)
- Aurora cluster identifiers (if RDBMS) or OpenSearch endpoints (if OpenSearch)

5. **Provide export block** for the user to copy-paste into their shell:
```bash
export CLUSTER_NAME="<from tfvars>"
export REGION_0="<from tfvars>"
export REGION_1="<from tfvars>"
export ALB_ENDPOINT_0="<terraform output -raw region_0_alb_endpoint>"
export ALB_ENDPOINT_1="<terraform output -raw region_1_alb_endpoint>"
```

## Troubleshooting

- **Aurora creation timeout:** Aurora Global DB can take 15+ minutes. If Terraform times out, run `terraform apply` again — it will pick up where it left off.
- **Insufficient capacity:** Some regions have limited Fargate capacity. Try a different AZ or region.
- **Permission errors:** Ensure your AWS credentials have admin-level access or the specific permissions for ECS, RDS, EC2, ELB, IAM, KMS, S3, CloudWatch, and Route 53.
- **DB seed task fails:** The one-time IAM DB user creation task runs as part of infra apply. Check CloudWatch log group `/ecs/<cluster_name>-r0-db-seed` if apply hangs after Aurora is ready.

## Success

Tell the user: "Infrastructure deployed. Proceed with `/ecs-dual-region/3-deploy-camunda` to deploy the Camunda app layer."
