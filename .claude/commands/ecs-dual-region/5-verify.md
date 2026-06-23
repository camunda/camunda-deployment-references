# Verify ECS Dual-Region Deployment (Step 5/6)

Comprehensive health check of the dual-region Camunda deployment.

## Pre-Checks

Read `aws_profile`, `cluster_name`, `secondary_storage_type` from infra tfvars:
```bash
cat aws/containers/ecs-dual-region-fargate/terraform/infra/terraform.tfvars
```

Get app-layer outputs (which re-export ALB/NLB endpoints):
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/app
terraform output
```

For Aurora identifiers, use the infra state directly:
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/infra
terraform output
```

## Camunda Context

A healthy dual-region deployment has: 8 brokers, 8 partitions, each partition with 4 replicas spread across both regions, and every partition with exactly one leader.

The ALB listens on **port 80** and forwards to the container on 8080.

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
cd aws/containers/ecs-dual-region-fargate/terraform/app
ALB_R0=$(terraform output -raw region_0_alb_endpoint)
curl -s "http://${ALB_R0}/v2/topology"
```

Check:
- `brokers` array has 8 entries: PASS/FAIL
- Each partition (1-8) has exactly one LEADER: PASS/FAIL
- Each partition has 4 replicas total: PASS/FAIL

### 3. Cross-Region Connectivity

```bash
ALB_R1=$(terraform output -raw region_1_alb_endpoint)

# Both ALBs respond
curl -sf "http://${ALB_R0}/v2/topology" > /dev/null && echo "Region 0 ALB: PASS" || echo "Region 0 ALB: FAIL"
curl -sf "http://${ALB_R1}/v2/topology" > /dev/null && echo "Region 1 ALB: PASS" || echo "Region 1 ALB: FAIL"
```

### 4. Secondary Storage Health

**If RDBMS (Aurora Global):**
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/infra
aws rds describe-global-clusters \
  --global-cluster-identifier $(terraform output -raw aurora_global_cluster_id) \
  [--profile <profile>] \
  --query 'GlobalClusters[0].{Status:Status,Members:GlobalClusterMembers[*].{Identifier:DBClusterIdentifier,IsWriter:IsClusterWriter}}'
```
PASS: Status is "available", one writer + one reader member.

**If OpenSearch:**
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/infra
OS_R0=$(terraform output -raw opensearch_region_0_endpoint)
curl -sf "https://${OS_R0}/_cluster/health" -u "<admin_user>:<admin_pass>" | jq '.status'
```
PASS: Status is "green" in both regions.

### 5. Optional Workflow Test

Deploy a simple process and verify it completes. The admin password is in the app state outputs:
```bash
cd aws/containers/ecs-dual-region-fargate/terraform/app
ADMIN_PASS=$(terraform output -raw admin_user_password)

curl -X POST "http://${ALB_R0}/v2/process-instances" \
  -H "Content-Type: application/json" \
  -u "admin:${ADMIN_PASS}" \
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

Tell the user: "Deployment verified. To tear down, run `/ecs-dual-region/6-cleanup`"
