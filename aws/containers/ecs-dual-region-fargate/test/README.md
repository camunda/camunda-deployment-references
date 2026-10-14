# ECS Dual-Region Fargate — Terratest End-to-End

End-to-end tests that apply the full three-state Terraform stack (`vpc/` → `infra/` → `app/`), wait for Camunda to reach steady state, and verify Zeebe Raft quorum forms across both regions. These tests create **real AWS resources** and cost real money — only run against the sandbox account.

Per `docs/superpowers/specs/2026-06-10-ecs-dual-region-testing-design.md` §2 (Sprint 4).

## What's here

| File | Test | What it proves |
|---|---|---|
| `src/dual_region_greenfield_rdbms_test.go` | `TestEndToEnd_Greenfield_TGW_RDBMS` | Apply with `networking_mode = transit_gateway` + `secondary_storage_type = rdbms`. Wait for 8 Zeebe brokers + one leader per partition. |
| `src/dual_region_greenfield_opensearch_test.go` | `TestEndToEnd_Greenfield_VpcPeering_OpenSearch` | Same workflow with the alternative combo: `vpc_peering` + `opensearch`. |
| `src/helpers/apply.go` | `ApplyAllThreeStates(...)` | Wraps `terraform init && apply` for `vpc/` → `infra/` → `app/` with proper `defer Destroy` cleanup in reverse order. |
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
| `TEST_CLUSTER_PREFIX` | suite prefix with a random suffix | Local override for `cluster_name`. CI ignores this override to keep concurrent suites separate. |
| `TEST_RAFT_TIMEOUT_MIN` | `30` | Minutes to wait for the 8-broker quorum to form. |
<<<<<<< HEAD
=======
| `TEST_RUN_ID` | unset | CI run ID. Adds `-run<id>` to the state group. The full base36 ID forms the resource-name suffix. |
>>>>>>> 10dae2f (fix(ecs): keep dual-region resource names unique per CI run (#3675))

## Cleanup

Each test does `defer terraform.Destroy(...)` for all three states in reverse order (app → infra → vpc). If the test panics or is killed, resources will leak — the daily cleanup workflow (`tests-daily-cleanup-aws-ecs-dual-region.yml`) sweeps anything tagged with `Test = "true"`. All tests apply this tag via `default_tags`.

To force a manual cleanup after a stuck run:

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/app && terraform destroy -auto-approve
cd ../infra && terraform destroy -auto-approve
cd ../vpc && terraform destroy -auto-approve
```

## CI integration

<<<<<<< HEAD
Triggered by `.github/workflows/tests-integration-aws-ecs-dual-region.yml` (per the design spec; not yet wired up — opt-in to add after a manual sandbox run validates the suite end-to-end). The BYO-VPC variant and the failover/failback variants come in Sprint 5.
=======
The workflows set `TEST_RUN_ID` to the GitHub run ID.
This separates state groups and lets cleanup select one run without selecting another.

CI resource prefixes use `e2e-<suite-code>-<base36-run-id>` and must fit within 14 characters.
The suite codes are `t` (RDBMS), `o` (OpenSearch), `b` (BYO-VPC), `p` (planned failover), and `u` (unplanned failover).
Failback uses `n` without a writer switch and `s` with a writer switch.
This keeps the full run ID inside the load-balancer prefix and the target-group prefix after Terraform truncation.
The failover workflow uses the same base36 suffix to select Aurora clusters for cleanup.
State keys retain the full decimal run ID, so the daily cleanup also finds earlier test stacks.
Local runs keep their existing suite prefixes, random six-character suffixes, and prefix overrides.

- `aws_ecs_dual_region_fargate_integration.yml` runs the greenfield tests on matching pull requests and manual dispatches.
- `aws_ecs_dual_region_fargate_failover.yml` runs the failover and failback tests on matching pull requests and manual dispatches.
- `aws_ecs_dual_region_fargate_byo_vpc.yml` runs the BYO-VPC test on manual dispatches.
- `aws_ecs_dual_region_fargate_daily_cleanup.yml` runs cleanup on its schedule, matching pull requests, and manual dispatches.

The failover suite has no schedule.
The local pre-commit hook runs only the offline helper tests.
These tests use fake CLI responses and do not create AWS resources.
>>>>>>> 10dae2f (fix(ecs): keep dual-region resource names unique per CI run (#3675))
