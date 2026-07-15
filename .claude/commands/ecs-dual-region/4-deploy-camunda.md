# Deploy Camunda on ECS Dual-Region (Step 4/6)

Apply the **app** Terraform layer (Camunda task definitions + ECS services), then monitor services reaching steady state and Zeebe Raft quorum formation.

## Pre-Checks

1. Read `aws_profile` and `cluster_name` from infra tfvars:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/infra/terraform.tfvars
```

2. Verify infra state exists:
```bash
test -f aws/containers/ecs-dual-region-fargate/terraform/infra/terraform.tfstate && echo OK
```
If missing, run `/ecs-dual-region/3-deploy-infra` first.

3. Verify ECS clusters exist (created by infra):
```bash
aws ecs describe-clusters --clusters <cluster_name>-r0-cluster --region <region_0> [--profile <profile>]
aws ecs describe-clusters --clusters <cluster_name>-r1-cluster --region <region_1> [--profile <profile>]
```
Both should return `ACTIVE`.

## Camunda Context

The infra layer created empty ECS clusters. This step deploys the actual Camunda workload:
- **4 Zeebe brokers per region** (8 total) participate in Raft consensus across regions
- **Raft quorum formation takes ~20 minutes** because brokers must discover each other cross-region via NLB
- **Replication factor 4** means every partition has copies in both regions — if one region goes down, the other has complete data
- **Connectors** (1 per region) start faster since they just connect to the local Zeebe gateway

## Steps

1. **Initialize Terraform (app state):**
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/app
terraform init
```

2. **Apply:**

Run in the background to avoid the 10-minute Bash tool limit (service stabilization can exceed it):
```bash
terraform apply -auto-approve > debug/app-apply.log 2>&1
```
Use `run_in_background: true` on the Bash tool call. You will be notified when it completes. To check interim progress: `tail -20 debug/app-apply.log`.

   App reads infra outputs via `terraform_remote_state` (default path: `../infra/terraform.tfstate`).

3. **Monitor orchestration cluster services:**
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

4. **Monitor connectors services:**
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

5. **Wait for Raft quorum (~20 minutes):**

Get the ALB endpoint from the app state (it re-exports infra outputs):
```bash
ALB_R0=$(terraform output -raw region_0_alb_endpoint)
```

Then poll the Zeebe topology endpoint (ALB listens on port **80**, forwards to container 8080):
```bash
curl -s "http://${ALB_R0}/v2/topology" | jq '.brokers | length'
```
Wait until this returns `8` (all brokers registered).

6. **Verify partition leaders:**
```bash
curl -s "http://${ALB_R0}/v2/topology" | jq '[.brokers[].partitions[] | select(.role == "LEADER")] | length'
```
Should return `8` (one leader per partition).

## Troubleshooting

- **Tasks keep stopping:** Check CloudWatch logs:
  ```bash
  LOG_GROUP=$(terraform output -raw region_0_log_group_name)
  aws logs tail "$LOG_GROUP" --since 10m --region <region_0> [--profile <profile>]
  ```
- **Raft doesn't form:** Verify cross-region NLB is reachable. Check security groups allow port 26502 between VPC CIDRs.
- **Aurora connection fails:** Verify the DB seed task succeeded during infra apply. Check CloudWatch log group `/ecs/<cluster_name>-r0-db-seed`.
- **Only some brokers register:** Some brokers may take longer. Wait up to 25 minutes before investigating.
- **App apply fails reading infra outputs:** Verify `infra_state_path` (default `../infra/terraform.tfstate`) points to a valid state file.

## Success

Tell the user: "Camunda is running. Proceed with `/ecs-dual-region/5-verify`"
