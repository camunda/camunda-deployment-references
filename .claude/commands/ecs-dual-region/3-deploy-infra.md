# Deploy ECS Dual-Region Infrastructure (Step 3/6)

Deploy the **infra** layer: Aurora Global / OpenSearch, ECS clusters, ALB/NLBs, KMS, S3, secrets, IAM. Consumes vpc outputs via `terraform_remote_state`. The Camunda app layer comes in step 4.

## Pre-Checks

1. Verify the vpc state has been applied (step 2):
```bash
test -f aws/containers/ecs-dual-region-fargate/terraform/vpc/terraform.tfstate && echo OK
```
If missing, tell the user to run `/ecs-dual-region/2-deploy-vpc` first.

2. Verify infra tfvars exists:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/infra/terraform.tfvars
```
If missing, tell the user to run `/ecs-dual-region/1-configure` first.

3. Extract `aws_profile` from tfvars for CLI commands. If set, use `--profile <value>` on all AWS CLI commands. If null/empty, omit the flag.

## Camunda Context

This step deploys everything *except* the Camunda task definitions and the VPC/networking (which lives in step 2):

- **Aurora Global Database** (if RDBMS) or **OpenSearch domains** (if OpenSearch) for secondary storage
- **ECS clusters** with Fargate capacity providers in both regions (no services yet)
- **Load balancers:** ALB (HTTP on port 80 → container 8080, management 9600), NLB external (gRPC 26500), NLB internal (Raft 26502)
- **IAM roles, KMS keys, S3 backup buckets, Secrets Manager**
- **One-time `db_seed` task** (RDBMS only) that creates the `camunda` IAM DB user and grants

VPC IDs, subnet IDs, CIDRs, peering/TGW IDs are read from `terraform/vpc/`'s state via `terraform_remote_state` (default path `../vpc/terraform.tfstate`).

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

Always run in the background — Aurora Global DB creation takes 15-25 minutes, well beyond the 10-minute Bash tool limit:
```bash
terraform apply -auto-approve > debug/infra-apply.log 2>&1
```
Use `run_in_background: true` on the Bash tool call. You will be notified when it completes. To check interim progress: `tail -20 debug/infra-apply.log`.

If the apply fails mid-run with `DBClusterAlreadyExistsFault`, import the orphaned cluster and re-apply:
```bash
terraform import -var-file=terraform.tfvars 'module.aurora_global[0].aws_rds_cluster.secondary' <cluster-id>
terraform apply -auto-approve > debug/infra-apply.log 2>&1
```

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

- **`terraform_remote_state` reads empty outputs:** vpc state hasn't been applied yet, or `var.vpc_state_path` points at the wrong file. Run `/ecs-dual-region/2-deploy-vpc` and confirm `terraform/vpc/terraform.tfstate` exists with the expected outputs (`terraform -chdir=../vpc output`).
- **Aurora creation timeout:** Aurora Global DB can take 15+ minutes. If Terraform times out, run `terraform apply` again — it will pick up where it left off.
- **Insufficient capacity:** Some regions have limited Fargate capacity. Try a different AZ or region (which means changing the vpc state too).
- **Permission errors:** Ensure your AWS credentials have admin-level access or the specific permissions for ECS, RDS, EC2, ELB, IAM, KMS, S3, CloudWatch.
- **DB seed task fails:** The one-time IAM DB user creation task runs as part of infra apply. Check CloudWatch log group `/ecs/<cluster_name>-r0-db-seed` if apply hangs after Aurora is ready.

## Success

Tell the user: "Infrastructure deployed. Proceed with `/ecs-dual-region/4-deploy-camunda` to deploy the Camunda app layer."
