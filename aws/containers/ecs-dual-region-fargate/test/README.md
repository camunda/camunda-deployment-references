# ECS Dual-Region Fargate — Terratest End-to-End

End-to-end tests that apply the full three-state Terraform stack (`vpc/` → `infra/` → `app/`), wait for Camunda to reach steady state, and verify Zeebe Raft quorum forms across both regions. These tests create **real AWS resources** and cost real money — only run against the sandbox account.

## What's here

| File | Test | What it proves |
|---|---|---|
| `src/dual_region_greenfield_rdbms_test.go` | `TestEndToEnd_Greenfield_TGW_RDBMS` | Apply with `networking_mode = transit_gateway` + `secondary_storage_type = rdbms`. Wait for 8 Zeebe brokers + one leader per partition. |
| `src/dual_region_greenfield_opensearch_test.go` | `TestEndToEnd_Greenfield_VpcPeering_OpenSearch` | Same workflow with the alternative combo: `vpc_peering` + `opensearch`. |
| `src/byo_vpc_test.go` | `TestEndToEnd_BYO_VPC_TGW_RDBMS` | Stands up the throwaway VPC pair in `aws/test-fixtures/byo-vpcs/`, then applies with `byo_vpc = true`. |
| `src/failover_test.go` | `TestPlannedFailover`, `TestUnplannedFailover` | Runs `procedure/failover.sh` and asserts the three things it changes: the failed region drained, the Aurora writer promoted to region 1, and the replication factor down from 4 to 2 — which is what proves the zone left the persisted distribution rather than merely going unreachable. The unplanned variant kills region 0 first and passes `--keep-tasks`. |
| `src/failback_test.go` | `TestFailback_NoSwitchWriter`, `TestFailback_SwitchWriter` | Failover (which promotes the writer itself), then `procedure/failback.sh` — asserting the replication factor recovers from 2 to 4, so the zone is genuinely back in the distribution, and that the writer settles where each `--switch-writer` variant expects. |
| `src/helpers/apply.go` | `ApplyAllThreeStates(...)` | Wraps `terraform init && apply` for `vpc/` → `infra/` → `app/` with proper `defer Destroy` cleanup in reverse order. |
| `src/helpers/raft.go` | `WaitForRaftQuorum(...)` | Polls `http://<alb>/v2/topology` (basic auth — 8.10 rejects unauthenticated `/v2/*`) until the expected brokers register and each partition has exactly one leader, or fails after a configurable timeout (default 30 min). |
| `src/helpers/procedure_env.go` | `ProcedureEnv(...)` | Sources `procedure/export_environment_prerequisites.sh` and reads back its exports, so the environment contract has one definition rather than a Go copy to keep in step. |
| `src/helpers/fixture.go` | `NewFixture(...)` | Resolves the `TEST_*` overrides and assembles the `ApplyOptions` every suite needs; the four suites differ only in networking mode, storage type, and a label. |
| `src/helpers/ecs.go` | `ScaleRegionServices(...)`, `RequireRegionScaledDown(...)` | Simulates a region outage and asserts on the service counts failover leaves behind. |

> **No test calls `t.Parallel()`.** They share three module directories on disk, and each provisions a full dual-region stack in shared CI regions — the second is the binding reason. See `src/doc.go`.

## Prerequisites

- Go ≥ 1.26 (`asdf install`)
- Terraform ≥ 1.6 on `PATH`
- AWS credentials for the `infraex` profile (or whatever `TEST_AWS_PROFILE` is set to) — sandbox account only
- ~$50–100 of AWS budget per run (Aurora Global + ECS Fargate + 2× NAT gateways for 30–60 minutes)

## Running locally

```bash
cd aws/containers/ecs-dual-region-fargate/test/src
go test -v -timeout 90m -run TestEndToEnd_Greenfield_TGW_RDBMS ./...
```

Override defaults with env vars:

| Variable | Default | Purpose |
|---|---|---|
| `TEST_AWS_PROFILE` | `infraex` | AWS profile to pass into each state's `aws_profile` tfvar |
| `TEST_REGION_0` | `eu-west-2` | Region 0 (overrideable for capacity issues) |
| `TEST_REGION_1` | `eu-west-3` | Region 1 |
| `TEST_CLUSTER_PREFIX` | random `e2e-XXXXXX` | Prefix passed to `cluster_name`. Determines AWS resource naming. |
| `TEST_RAFT_TIMEOUT_MIN` | `30` | Minutes to wait for the 8-broker quorum to form. |

## Cleanup

Each test does `defer terraform.Destroy(...)` for all three states in reverse order (app → infra → vpc). If the test panics or is killed, resources will leak — `.github/workflows/aws_ecs_dual_region_fargate_daily_cleanup.yml` sweeps clusters whose state is older than 12 hours. All tests tag their resources `Test = "true"` via `default_tags`.

To force a manual cleanup after a stuck run:

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/app && terraform destroy -auto-approve
cd ../infra && terraform destroy -auto-approve
cd ../vpc && terraform destroy -auto-approve
```

## CI integration

| Workflow | Trigger | Covers |
|---|---|---|
| `aws_ecs_dual_region_fargate_tests.yml` | pull request + dispatch | The happy path, and the only lane that runs on PRs. Deploys greenfield `vpc_peering` + `rdbms`, proves process instances execute, then drives `failover.sh` and `failback.sh` against that same cluster, re-proving execution after each transition. Does not use this Terratest suite. |
| `aws_ecs_dual_region_fargate_integration.yml` | dispatch | The two greenfield shapes, one test per runner leg. |
| `aws_ecs_dual_region_fargate_failover.yml` | dispatch | The four failover/failback tests, one per runner leg. Installs `session-manager-plugin`: the scripts reach the management API over ECS Exec, since port 9600 is not exposed through the ALB. |
| `aws_ecs_dual_region_fargate_byo_vpc.yml` | dispatch | `TestEndToEnd_BYO_VPC_TGW_RDBMS`. |
| `aws_ecs_dual_region_fargate_golden.yml` | pull request + dispatch | Golden plan comparison for all three states. No AWS resources created. |
| `aws_ecs_dual_region_fargate_daily_cleanup.yml` | daily + dispatch | Sweeps leaked clusters, including the post-failover Aurora teardown. |

The dispatch-only workflows stay dispatch-only on purpose: each test provisions its own full stack, so running a suite is several clusters' worth of spend. They matrix one test per runner — a single `go test ./...` would be several hours of serial wall clock — with `max-parallel` bounding how many stacks exist at once. The PR lane deliberately covers one combination on one cluster.
