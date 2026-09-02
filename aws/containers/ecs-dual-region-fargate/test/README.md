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
| `TEST_CLUSTER_PREFIX` | random `e2e-XXXXXX` | Prefix passed to `cluster_name`. Determines AWS resource naming. |
| `TEST_RAFT_TIMEOUT_MIN` | `30` | Minutes to wait for the 8-broker quorum to form. |

## Cleanup

Each test does `defer terraform.Destroy(...)` for all three states in reverse order (app → infra → vpc). If the test panics or is killed, resources will leak — the daily cleanup workflow (`tests-daily-cleanup-aws-ecs-dual-region.yml`) sweeps anything tagged with `Test = "true"`. All tests apply this tag via `default_tags`.

To force a manual cleanup after a stuck run:

```bash
cd aws/containers/ecs-dual-region-fargate/terraform/app && terraform destroy -auto-approve
cd ../infra && terraform destroy -auto-approve
cd ../vpc && terraform destroy -auto-approve
```

## CI integration

Triggered by `.github/workflows/tests-integration-aws-ecs-dual-region.yml` (per the design spec; not yet wired up — opt-in to add after a manual sandbox run validates the suite end-to-end). The BYO-VPC variant and the failover/failback variants come in Sprint 5.
