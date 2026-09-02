# Cleanup ECS Dual-Region Deployment (Step 6/6)

Destroy all resources. With the 3-state layout, destroy in **reverse order**: app first (drains ECS services), then infra, then vpc.

## Pre-Checks

1. Read `aws_profile` and `cluster_name` from infra tfvars:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/infra/terraform.tfvars
```

2. Check whether vpc was created here or supplied (BYO):
```bash
grep -E "^byo_vpc\s*=" aws/containers/ecs-dual-region-fargate/terraform/vpc/terraform.tfvars
```
- If `byo_vpc = true`, the vpc destroy will only tear down peering/TGW (not the VPCs themselves — those belong to the customer).
- If absent or `false`, vpc destroy removes everything including the VPCs.

3. **Confirm with user:** "This will destroy ALL resources including ECS clusters, databases, load balancers, S3 buckets, and (greenfield only) VPCs. This action cannot be undone. Proceed? (yes/no)"

Do NOT proceed without explicit user confirmation.

## Steps

1. **Destroy the app layer first** (ECS task definitions, services, EFS, Service Connect):

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/app
terraform destroy
```

Show the plan and confirm with the user before typing "yes" (or run with `-auto-approve` once they've reviewed).

Destroying the app layer scales the services to 0 and drains tasks gracefully. Takes 2-5 minutes.

2. **Destroy the infra layer:**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/infra
terraform destroy
```

This takes 10-20 minutes (Aurora Global DB deletion is the bottleneck).

3. **Destroy the vpc layer:**

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/vpc
terraform destroy
```

- Greenfield: removes 2 VPCs, subnets, NAT/IGW, plus peering/TGW. Takes 2-5 minutes.
- BYO-VPC: removes only peering/TGW and any Route 53 Resolver endpoints. < 1 minute. The customer-provided VPCs are untouched.

4. **Verify no orphaned resources:**

If terraform destroy fails on VPC deletion (greenfield mode), it's usually orphaned ENIs from ECS/Lambda:

```bash
# Check for orphaned ENIs in region 0
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
- Then retry `terraform destroy` in `terraform/vpc`.

## Troubleshooting

- **App destroy fails because infra/vpc is gone:** Each layer reads upstream state via `terraform_remote_state`. If you destroyed out of order by accident, restore the upstream state file from backup or `terraform state rm` everything in the downstream state and remove orphaned AWS resources via the console.
- **S3 bucket non-empty error:** Set `s3_force_destroy = true` in `terraform/infra/terraform.tfvars` and re-run infra destroy. Or empty the bucket manually.
- **Aurora deletion protection:** If apply set `deletion_protection = true`, disable it first via the AWS console or `aws rds modify-db-cluster`.
- **vpc destroy fails on TGW peering attachment in use:** Peering routes in private route tables block the attachment delete. Ensure infra destroy completed cleanly (it removes the ECS clusters that depended on the routes); then re-run vpc destroy.

## Success

Tell the user: "All resources destroyed."
