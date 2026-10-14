# ECS Dual-Region Fargate — Terratest End-to-End

End-to-end tests that apply the full three-state Terraform stack (`vpc/` → `infra/` → `app/`), wait for Camunda to reach steady state, and verify Zeebe Raft quorum forms across both regions. These tests create **real AWS resources** and cost real money — only run against the sandbox account.

Per `docs/superpowers/specs/2026-06-10-ecs-dual-region-testing-design.md` §2 (Sprint 4).

## What's here

| File | Test | What it proves |
|---|---|---|
| `src/dual_region_greenfield_rdbms_test.go` | `TestEndToEnd_Greenfield_TGW_RDBMS` | Apply with `networking_mode = transit_gateway` + `secondary_storage_type = rdbms`. Wait for 8 Zeebe brokers + one leader per partition. |
| `src/dual_region_greenfield_opensearch_test.go` | `TestEndToEnd_Greenfield_VpcPeering_OpenSearch` | Same workflow with the alternative combo: `vpc_peering` + `opensearch`. |
| `src/helpers/apply.go` | `ApplyAllThreeStates(...)` | Applies `vpc/` → `infra/` → `app/`. Registers each destroy with `t.Cleanup` before apply. |
| `src/helpers/raft.go` | `WaitForRaftQuorum(...)` | Polls `http://<alb>/v2/topology` until 8 brokers register and each of the 8 partitions has exactly one leader, or fails after a configurable timeout (default 30 min). |

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
| `TEST_RUN_ID` | unset | CI run ID. Adds `-run<id>` to the state group. Its last six digits form the resource-name suffix. |

## Cleanup

Each test copies Terraform into an isolated temporary directory.
The helper registers each destroy with `t.Cleanup` before apply.
Cleanup runs in reverse order: app → infra → vpc → BYO fixture, when present.
An interrupted process can leave resources behind because its cleanup cannot run.

The S3 backend stores each layer under `aws/containers/ecs-dual-region-fargate/tfstate-<prefix>[-run<id>]/<layer>/terraform.tfstate`.
The optional `-run<id>` suffix comes from `TEST_RUN_ID`.
The layers are `app`, `infra`, `vpc`, and `fixture` for BYO-VPC tests.

Each CI workflow runs a cleanup step for its exact `run<id>/` state-key target.
The scheduled workflow `aws_ecs_dual_region_fargate_daily_cleanup.yml` reclaims old state groups after interrupted runs.
Both use `aws-generic-terraform-cleanup` and the architecture's `terraform/cleanup/config-dual-region-fargate` provider configuration.

For manual cleanup, dispatch the daily cleanup workflow with the required maximum state age.
It selects all state groups older than that threshold, not only one test.
Do not run destroy against the source directories.
Their backend configuration does not identify the isolated test states.

## CI integration

The workflows set `TEST_RUN_ID` to the GitHub run ID.
This separates state groups and lets cleanup select one run without selecting another.

- `aws_ecs_dual_region_fargate_integration.yml` runs the greenfield tests on matching pull requests and manual dispatches.
- `aws_ecs_dual_region_fargate_failover.yml` runs the failover and failback tests on matching pull requests and manual dispatches.
- `aws_ecs_dual_region_fargate_byo_vpc.yml` runs the BYO-VPC test on manual dispatches.
- `aws_ecs_dual_region_fargate_daily_cleanup.yml` runs cleanup on its schedule, matching pull requests, and manual dispatches.

The failover suite has no schedule.
The local pre-commit hook runs only the offline helper tests.
These tests use fake CLI responses and do not create AWS resources.
