# Cleanup ECS Dual-Region Deployment (Step 5/5)

Destroy all resources. With the split state layout, destroy in **reverse order**: app first (removes ECS services, which drains tasks), then infra (removes everything else).

## Pre-Checks

1. Read `aws_profile` and `cluster_name` from infra tfvars:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/infra/terraform.tfvars
```

2. **Confirm with user:** "This will destroy ALL resources including ECS clusters, databases, load balancers, and S3 buckets. This action cannot be undone. Proceed? (yes/no)"

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

3. **Verify no orphaned resources:**

If terraform destroy fails on VPC deletion, it's usually orphaned ENIs from ECS/Lambda:

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
- Then retry `terraform destroy` in `terraform/infra`.

## Troubleshooting

- **App destroy fails because infra is gone:** The app state reads infra outputs via `terraform_remote_state`. If infra was destroyed first by accident, manually remove app resources from the AWS console, then `terraform state rm` everything in the app state.
- **S3 bucket non-empty error:** Set `s3_force_destroy = true` in `terraform/infra/terraform.tfvars` and re-run infra destroy. Or empty the bucket manually.
- **Aurora deletion protection:** If apply set `deletion_protection = true`, disable it first via the AWS console or `aws rds modify-db-cluster`.

## Success

Tell the user: "All resources destroyed."
