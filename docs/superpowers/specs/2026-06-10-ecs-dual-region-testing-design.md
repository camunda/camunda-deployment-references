# ECS Dual-Region Fargate — Test Strategy Design

**Date:** 2026-06-10
**Status:** Approved (open questions resolved 2026-06-10)
**Branch:** feat/ecs-dual-region-rdbms

## Goal

Define a two-layer test strategy for the ECS dual-region reference architecture so that:

1. **Validation logic and plan structure** is verified on every PR in seconds, with no AWS calls (`terraform test` + `mock_provider`).
2. **End-to-end behavior** (Raft quorum, Aurora Global, failover/failback, BYO-VPC contract) is verified on a slower cadence against real AWS (Terratest).

The `check` blocks introduced in the vpc-state split (PR 1, commit `2aae6d95`) currently have no automated coverage — they could silently regress to no-ops. Closing that gap is the immediate driver.

## Motivation

What the repo has today:
- Per-module Terratest under `aws/modules/*/test/` (ci + golden plan fixtures).
- Top-level integration workflows in `.github/workflows/aws_ecs_dual_region_*` that apply the full stack daily/weekly.
- `tflint`, `terraform fmt`, `terraform validate`, `trivy`, `pre-commit` hooks.

What it lacks:
- Any `.tftest.hcl` files. The `terraform test` framework (GA in TF 1.6, mocks in 1.7) is unused. Variable validation and `check` blocks have no regression coverage.
- Tests at the **root-state** level. `vpc/`, `infra/`, and `app/` are only exercised by full integration workflows — too slow to fail fast on regressions.
- A BYO-VPC end-to-end test path. PR 3's BYO branch is currently a "we wrote the validation, hopefully it works" feature.

## Scope

### In Scope
- `.tftest.hcl` files for `vpc/`, `infra/`, `app/`, and each module under `aws/modules/`.
- New root-state Terratest suite under `aws/containers/ecs-dual-region-fargate/test/`.
- BYO-VPC Terratest with pre-created sandbox VPCs.
- Failover / failback Terratest covering the `procedure/failover.sh` and `procedure/failback.sh` scripts.
- New `Internal - Lint - Terraform Test` GitHub Actions workflow running all `terraform test` files on every PR.
- New `Tests - BYO-VPC - AWS ECS Dual Region` workflow on a less-frequent schedule.

### Out of Scope
- Replacing existing module Terratest. Keep it; add `.tftest.hcl` alongside.
- Property-based / fuzz testing of variables. Per-variable regex `validation` covers the realistic input space.
- Sentinel / OPA policy testing. `check` blocks plus the existing `trivy` scan cover policy needs.
- Performance testing of Camunda itself. That's a Camunda-team responsibility, not infra.

---

## 1. `terraform test` — fast hermetic coverage

### 1.1 Conventions

- One `tests/` directory per state and per module.
- One `.tftest.hcl` file per logical concern (validation, branching, output contract). Avoid one giant file per state.
- Always use `mock_provider "aws"` at the top of each test file. We are testing Terraform behavior, not AWS API behavior.
- Use `override_data` blocks to stub `terraform_remote_state` reads. This is what lets `infra/` and `app/` tests run without applying upstream states.
- Use `expect_failures` lists to assert that a specific `check` block or variable `validation` fires. Never use `expect_failures` to allow any error — always pin to a specific address.

### 1.2 `terraform/vpc/tests/`

| File | Test name | Asserts |
|---|---|---|
| `validation.tftest.hcl` | `byo_vpc_required_inputs_fail` | `byo_vpc=true` with empty subnets → `expect_failures = [check.byo_vpc_required_inputs]` |
| | `create_vpc_inputs_clean_fail` | `byo_vpc=false` with stray `region_0_vpc_id` → `expect_failures = [check.create_vpc_inputs_clean]` |
| | `vpc_id_regex_rejects_malformed` | `region_0_vpc_id = "nope"` → variable validation fails |
| | `subnet_id_regex_rejects_malformed` | Bad `subnet-` entry → fails |
| | `route_table_id_regex_rejects_malformed` | Bad `rtb-` entry → fails |
| | `cidr_validation_rejects_garbage` | `region_0_vpc_cidr = "not-a-cidr"` → fails |
| | `networking_mode_rejects_invalid` | `networking_mode = "magic"` → fails |
| `greenfield.tftest.hcl` | `default_plan_succeeds` | All defaults + `cluster_name` → plan green |
| | `vpc_peering_mode_no_tgw` | `networking_mode = "vpc_peering"` → `length(module.transit_gateway) == 0`, peering connection planned |
| | `transit_gateway_mode_no_peering` | Inverse |
| | `single_nat_propagates` | `single_nat_gateway = true` → module receives the value |
| | `cross_region_dns_off_skips_resolver_sgs` | Default → 0 resolver SGs |
| | `cross_region_dns_on_creates_resolver_sgs` | `enable_cross_region_dns_resolver = true` → 1 SG per region |
| `byo.tftest.hcl` | `byo_passthrough_outputs` | Complete BYO inputs → `output.region_0_vpc_id == var.region_0_vpc_id` etc. |
| | `byo_peering_still_created` | BYO + `vpc_peering` → peering connection planned between supplied VPC IDs |
| | `byo_skips_vpc_module` | `length(module.vpc_region_0) == 0` |
| | `byo_with_tgw_creates_attachments` | BYO + `transit_gateway` → VPC attachments target supplied subnets |

### 1.3 `terraform/infra/tests/`

Override the vpc remote state with a canonical fixture so the tests stay readable.

```hcl
override_data {
  target = data.terraform_remote_state.vpc
  values = {
    outputs = {
      region_0_vpc_id                  = "vpc-aaaaaaaa"
      region_0_vpc_cidr                = "10.50.0.0/16"
      region_0_private_subnet_ids      = ["subnet-1a", "subnet-1b", "subnet-1c"]
      # ... etc.
    }
  }
}
```

| File | Test | Asserts |
|---|---|---|
| `validation.tftest.hcl` | `secondary_storage_type_rejects_invalid` | `"magic"` → variable validation fails |
| `storage_branch.tftest.hcl` | `rdbms_creates_aurora_only` | Default → `module.aurora_global` has count 1, `module.opensearch_region_0` has count 0 |
| | `opensearch_creates_search_only` | Inverse |
| | `rds_db_connect_only_when_rdbms` | `aws_iam_policy.rds_db_connect_region_0` count = 1 for RDBMS, 0 for OpenSearch |
| `vpc_consumption.tftest.hcl` | `consumes_stubbed_vpc_outputs` | Aurora `primary_vpc_id` equals injected `vpc-aaaaaaaa` |
| | `azs_derived_from_subnets` | Inject subnets in 3 specific AZs → `local.region_0_azs` returns those 3 |
| `iam.tftest.hcl` | `secrets_policy_includes_registry_when_credentials_supplied` | `registry_username` set → policy resources include registry secret ARN |
| | `secrets_policy_excludes_registry_when_empty` | `registry_username = ""` → policy excludes it |

### 1.4 `terraform/app/tests/`

Override the infra remote state with a canonical fixture.

| File | Test | Asserts |
|---|---|---|
| `env_branch.tftest.hcl` | `rdbms_env_vars_set` | `infra.secondary_storage_type = "rdbms"` → JDBC env vars present, ES env vars absent |
| | `opensearch_env_vars_set` | Inverse |
| `image_propagation.tftest.hcl` | `camunda_image_override_reaches_task_def` | `camunda_image = "my-registry/x:1.0"` → ECS task definition uses it |
| | `default_image_when_unset` | Default image used otherwise |
| `connectors.tftest.hcl` | `connectors_use_spring_profile` | `SPRING_PROFILES_ACTIVE = connectors` set in connector container env |
| | `connectors_health_path` | Target group health check path starts with `/connectors/` |
| `zone_aware.tftest.hcl` | `cluster_zone_env_per_region` | `CAMUNDA_CLUSTER_ZONE` set to `local.infra.region_0` (region 0 task) and `region_1` (region 1 task). Catches `CAMUNDA_CLUSTER_REGION` regression. |

### 1.5 `aws/modules/*/tests/`

Add a small `.tftest.hcl` per module covering variable validation only. Module-level integration stays in Terratest.

| Module | Test |
|---|---|
| `aurora-global` | `engine_version_regex`, `master_password_length`, `primary_num_instances_in_range`, `iam_auth_enabled_toggle_outputs` |
| `transit-gateway` | `prefix_required`, `peering_attachment_planned`, `default_route_table_outputs_non_null` |
| `ecs/fargate/orchestration-cluster` | `image_regex`, `restore_enabled_creates_init_container`, `internal_nlb_raft_listener_toggle` |
| `ecs/fargate/connectors` | `image_regex`, `secondary_storage_type_branches` |

---

## 2. Terratest — real-AWS truth

Keep what exists at the module level. Add **end-to-end** at the root-state level.

### 2.1 New directory: `aws/containers/ecs-dual-region-fargate/test/`

Match the existing module test layout (Go, terratest, golden plan fixtures alongside).

| File | Test | What it proves |
|---|---|---|
| `dual_region_greenfield_rdbms_test.go` | `TestEndToEnd_Greenfield_TGW_RDBMS` | Apply vpc → infra → app; wait Raft quorum; `curl /v2/topology` returns 8 brokers; one leader per partition |
| `dual_region_greenfield_opensearch_test.go` | `TestEndToEnd_Greenfield_VpcPeering_OpenSearch` | Same with the other secondary storage + networking combo |
| `byo_vpc_test.go` | `TestEndToEnd_BYO_VPC_TGW_RDBMS` | Pre-create two VPCs in setup, write BYO tfvars, apply vpc → infra → app, verify, destroy. Confirms the BYO contract end-to-end. |
| `failover_test.go` | `TestPlannedFailover` | After a full deploy, run `procedure/failover.sh`. Assert Aurora writer switched, broker quorum reformed within ~30s |
| | `TestUnplannedFailover` | `failover.sh --unplanned`. Assert detach + promote semantics |
| `failback_test.go` | `TestFailback_NoSwitchWriter` | After failover, run `failback.sh`. Assert cluster healthy with writer still in region 1 |
| | `TestFailback_SwitchWriter` | `failback.sh --switch-writer`. Assert writer moved back to region 0 |

### 2.2 Shared helpers (`test/helpers/`)

| Helper | Purpose |
|---|---|
| `apply_three_states.go` | Wraps `terraform init && apply` for `vpc/` → `infra/` → `app/` in sequence with shared workspace. Handles cleanup via `defer` even on partial failure. |
| `wait_for_raft_quorum.go` | Polls `/v2/topology` until 8 brokers + 8 partition leaders, or timeout. Reusable across all e2e tests. |
| `byo_vpc_setup.go` | Creates two throwaway VPCs (3 private + 3 public subnets each, NAT, IGW) via a separate `aws/test-fixtures/byo-vpcs/` Terraform config. Returns the IDs for plugging into the test's BYO tfvars. |

### 2.3 Cleanup discipline

Real-AWS tests can leak. Conventions:
- All tests `defer terraform.Destroy(...)` for every state they applied, in reverse order.
- `Tests - Daily Cleanup - AWS ECS Dual Region` workflow (existing pattern) extended to also sweep `byo-vpcs/` fixtures by tag.
- Resource tag: every Terratest run adds `Test = "true"` and `RunID = "<uuid>"` via `default_tags`, so the daily cleanup can target test artifacts without touching real deploys.

---

## 3. CI integration

| Hook / Workflow | Runs | When |
|---|---|---|
| `pre-commit` (`terraform_test` hook) | `terraform test` on touched states only | Every commit. ~10-30s. |
| `Internal - Lint - Terraform Test` (NEW) | All `terraform test` files across the repo. Gated by the standard `triage` job + `internal-triage-skip` action so the skip label (`skip_internal_lint_terraform_test`) honors the existing PR skip pattern. | Every PR. < 2 min. |
| `Tests - Integration - AWS ECS Dual Region` (existing) | Module Terratest + greenfield root-state Terratest | Daily per Camunda version, per the existing scheduler |
| `Tests - BYO-VPC - AWS ECS Dual Region` (NEW) | Only the BYO root-state Terratest | Weekly. The byo-vpcs setup adds ~5 minutes per run. |
| `Tests - Failover - AWS ECS Dual Region` (NEW) | Failover + failback Terratest. One Camunda version per week, rotating across the supported set (8.7, 8.8, 8.9, 8.10). | Weekly. These tests run on top of the greenfield apply so they need a longer slot. |

### 3.1 Pre-commit integration

The community `terraform_test` pre-commit hook (in `pre-commit-terraform`) is not yet a stable entry as of this writing. Use a shell wrapper instead:

```yaml
- id: terraform-test
  name: Terraform test (touched states)
  entry: scripts/run-terraform-test-touched.sh
  language: script
  pass_filenames: false
  files: \.tf$|\.tftest\.hcl$
```

`scripts/run-terraform-test-touched.sh` derives which `tests/` directories' parents were touched in the staged diff and runs `terraform test` only in those directories.

---

## 4. Sequencing

Five sprints, totaling roughly 10 working days of focused effort.

| Sprint | Scope | Effort |
|---|---|---|
| 1 | `terraform/vpc/tests/` — validation + greenfield + byo. Pre-commit wiring. New lint workflow. | 1 day |
| 2 | `terraform/infra/tests/` + `terraform/app/tests/` | 2 days |
| 3 | `aws/modules/*/tests/` — small validation tests per module | 2 days |
| 4 | Root-state Terratest in `aws/containers/ecs-dual-region-fargate/test/` — greenfield happy paths | 3 days |
| 5 | Failover/failback Terratest + BYO-VPC e2e | 2 days |

Sprint 1 is the highest-leverage individual chunk — it closes the validation-coverage gap that opened with PR 1.

---

## 5. Validation of this plan

Before declaring any sprint done:

- `terraform test` files: each failure case **must actually fail without the corresponding code in place**. Strategy: temporarily delete the `check` block / `validation` rule and confirm the test goes red. Otherwise the test is a no-op confirming "yes, valid input is valid."
- Terratest cases: a manual smoke run against a sandbox account before adding to the schedule. CI rate limits are precious.

---

## 6. Open Questions (resolved)

- **Q1.** ✅ `byo-vpcs/` fixtures live at `aws/test-fixtures/byo-vpcs/`. Keeps test infra out of the reference architecture tree and reusable by future tests.
- **Q2.** ✅ Failover Terratest rotates one Camunda version per week across {8.7, 8.8, 8.9, 8.10}. Schedule defined in `.github/workflows-config/workflow-scheduler.yml`.
- **Q3.** ✅ `Internal - Lint - Terraform Test` is gated by the standard `triage` job and `internal-triage-skip` action. Skip label: `skip_internal_lint_terraform_test`.

## 7. References

- VPC state split design: `docs/superpowers/specs/2026-06-09-vpc-state-split-design.md`
- Terraform test framework: https://developer.hashicorp.com/terraform/language/tests
- Mock providers: https://developer.hashicorp.com/terraform/language/tests/mocking
- Terratest: https://terratest.gruntwork.io/
- Existing module test layout: `aws/modules/aurora-global/test/`
