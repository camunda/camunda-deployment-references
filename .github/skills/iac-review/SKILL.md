---
name: iac-review
description: 'Review an infrastructure diff for security and correctness defects that this repository''s deterministic gates do not catch: Terraform/HCL, GitHub Actions workflows and composite actions, and `.github/` configuration YAML. USE WHEN: the user invokes "/iac-review", says "IaC review", "terraform review", "workflow security review", or the review-loop skill reaches its self-review step on a diff touching `*.tf`, `*.tfvars`, `*.hcl`, `.github/workflows/**`, `.github/actions/**`. INVOKES: git diff, ripgrep. DO NOT USE FOR: maintainability review (code-quality-review owns that), re-reporting what pre-commit already blocks, or approving/merging PRs.'
argument-hint: '[base-ref] (defaults to the merge base with the target branch)'
---

# IaC Review

A security-and-correctness pass over an infrastructure diff, run **before**
asking for a machine review.

This repository is 204 `*.tf`, 196 `*.yml` and 51 workflows. Those two surfaces
carry nearly all of its risk, and they are reviewed generically today. This
skill applies rules written specifically for them — but only for the residual
that the deterministic gates provably leave open.

Adapted from the review rule documents in
[alibaba/open-code-review](https://github.com/alibaba/open-code-review)
(`internal/config/rules/rule_docs/{terraform,github_workflows,github_config,yaml}.md`),
Apache License 2.0. The full license text and the list of changes are in
[NOTICE](./NOTICE), as Apache-2.0 requires.

## When to use

- Step 2 of the [review-loop](../review-loop/SKILL.md), alongside
  [code-quality-review](../code-quality-review/SKILL.md): that skill asks
  "is this well built?", this one asks "is this safe and correct?".
- On demand, before pushing a change to Terraform or to CI.

## Scope

| Path | Checks |
|---|---|
| `**/*.{tf,tfvars,hcl}` | [Terraform](#1-terraform--hcl) |
| `.github/workflows/**/*.{yml,yaml}`, `.github/actions/**/*.{yml,yaml}` | [Workflows](#2-github-actions) |
| `.github/*.{yml,yaml}`, `.github/ISSUE_TEMPLATE/**` | [Repo config](#3-github-configuration) |
| any other `*.{yml,yaml}` | [YAML](#4-yaml) |

## What the gates already own

**Do not report anything in this table.** It is already blocked before review,
so a finding here is pure noise — and worse, it teaches the reader to distrust
the report.

| Gate | Owns |
|---|---|
| `zizmor` (`--min-severity=high`, `.github/zizmor.yml`) | template injection, excessive permissions, credential persistence, dangerous triggers, unpinned action refs (policy `'*': hash-pin`) |
| `actionlint` | workflow schema, expression syntax, embedded shell — **`.github/workflows/` only** |
| `shellcheck` | shell correctness (`--exclude=SC2155`) |
| `terraform fmt`, `terraform-docs` | HCL formatting, module READMEs |
| `tflint` (`.lint/tflint/.tflint.hcl`) | naming convention |
| `trivy config` | Terraform misconfiguration — **only** in directories holding a `README.md`, at least one `*.tf`, and no `.trivy_ignore`, skipping `.terraform`, `.test`, `test`, `fixtures` |
| `detect-private-key`, `check-added-large-files` | committed keys, stray blobs |
| `yamllint`, `yamlfmt` | YAML style |
| `.lint/*` | cleanup coverage, reporter coverage, matrix skip guard, action vars, path filters |

## Where the gaps actually are

This is the whole justification for the skill. Each gap is a deliberate
configuration choice in this repository, not an oversight:

- **`tflint` runs four rules disabled** in `.lint/tflint/.tflint.hcl`:
  `terraform_unused_declarations`, `terraform_required_version`,
  `terraform_required_providers`, `terraform_typed_variables`.
- **`trivy` does not see every module** — see its row above. Terraform under
  `test/`, `fixtures/`, or in a directory with no `README.md` gets no
  misconfiguration scan at all.
- **`zizmor` is capped at `high`.** `.github/zizmor.yml` records that the
  repository knowingly carries medium and low findings (`artipacked`,
  `${{ steps.*.outputs }}` interpolation). It also runs offline, which skips
  `known-vulnerable-actions`, `impostor-commit`, `ref-confusion`,
  `ref-version-mismatch` and `stale-action-refs`, and it ignores
  `dangerous-triggers` for two named workflows.
- **`actionlint` never reads `.github/actions/`**, where most of this
  repository's shell lives.
- **Nothing enforces the `AGENTS.md` rules** in [section 5](#5-repository-rules-nothing-enforces).

## Precision bias

Favour precision over recall. Raise an issue only when you are confident it is
a real defect; stay silent when the surrounding context is unclear. A false
alarm costs more reviewer trust than a missed minor issue. Review only what is
observable in the diff — do not infer runtime provider behaviour, cloud account
configuration, or state stored elsewhere.

## Non-goals

These are reference architectures: demos and learning blueprints, not a
product. That cuts both ways.

- **Do not** demand production hardening the deployment never claimed — a
  missing WAF, a single-AZ demo, a short retention window. `AGENTS.md` is
  explicit that these are not production-ready.
- **But do** report insecure defaults anyway when they are the thing a reader
  copies. A demo that ships `0.0.0.0/0` on port 22, or a wildcard IAM policy,
  propagates into real deployments. "It is only a demo" is not a reason to
  stay silent about a pattern that teaches the wrong habit; it *is* a reason
  not to file the absence of enterprise controls.
- **Do not** flag cross-provider duplication — intentional here.
- **Do not** review maintainability, file size, or abstraction quality.
  [code-quality-review](../code-quality-review/SKILL.md) owns those.

## Checks

Report a finding only when it is actionable. An empty report is a valid result.

### 1. Terraform / HCL

**Secrets**

- A literal password, API key, access-key pair, private key, or connection
  string assigned to a resource argument, a `variable` default, or a `locals`
  entry instead of coming from a secret manager or an environment-backed
  data source.
- A `*.tfvars` file assigning a real-looking secret rather than a placeholder —
  `.tfvars` is the conventional home for real values and the usual accident.
- A `variable` that clearly holds a credential (name or description implies
  password, token, key, secret) missing `sensitive = true`.

**Permissions** — trivy owns this inside the module directories it scans; apply
it where trivy does not reach:

- A security group, firewall, or network ACL rule with an unrestricted source
  (`0.0.0.0/0`, `::/0`, `"*"`) on a sensitive port (22, 3389, database ports)
  or on all ports.
- An IAM policy, role, or resource policy granting `"Action": "*"` or
  `"Resource": "*"` instead of a scoped permission set.
- Public read/write ACLs or public-access settings on a storage resource with
  no stated public-content purpose.

**State and lifecycle**

- A `terraform.tfstate` or `*.tfstate.backup` in the diff — state holds
  resource attributes and secrets in plaintext and is never committed.
- Removing or weakening `lifecycle { prevent_destroy = true }` on a stateful
  resource (database, persistent volume, KMS key) with no explanation.
- A stateful resource created without lifecycle protection when sibling
  resources of the same kind in the diff do have one — an inconsistency to
  raise, not an absolute rule.

**Reproducibility** — `tflint`'s `required_version` and `required_providers`
rules are disabled here, so this is unguarded:

- A `required_providers` entry or module `source` left with no version
  constraint where sibling entries in the same file pin one. A deliberately
  wide but documented constraint (`~>`, an explicit range) is fine.

**Declarations** — `terraform_unused_declarations` is disabled here:

- A `variable` or `output` declared in the diff's module and read by nothing.
- A referenced variable never declared in the diff's scope.
- Duplicate resource or data-source labels in one module.

### 2. GitHub Actions

Assume `zizmor` and `actionlint` already passed. Report only:

**Security below the gate**

- A finding in `.github/actions/**`, which `actionlint` does not read.
- A medium/low-severity pattern that `zizmor` carries by policy but that this
  diff *introduces* rather than inherits — a new `artipacked` checkout, a new
  `${{ steps.*.outputs.* }}` interpolated straight into `run:`. Report as
  SHOULD-FIX, never BLOCKING: the threshold is a deliberate choice.
- An action reference that zizmor's offline run cannot audit — a SHA pinned to
  a repository that is archived, renamed, or whose tag has moved. Worth one
  look when a diff adds a third-party action.
- A secret reaching a step that does not need it, or interpolated into a place
  it can be echoed.

**Correctness**

- `actions/checkout` without `fetch-depth: 0` in a job that needs history
  (tags, merge-base, changelog).
- An `if:` whose boolean logic does not say what the surrounding comment or
  job name claims — especially `github.event_name` comparisons.
- A misspelled action input: unknown inputs are **silently ignored**, so
  `fetch-detph` fails open and nothing complains.
- A `needs:` naming a job id that does not exist in the same workflow.

**Reliability**

- A job that provisions or holds cloud resources with no `timeout-minutes`. A
  hung `terraform apply` keeps real infrastructure billing until the six-hour
  default expires. Do not flag short bookkeeping jobs — triage, labelling,
  matrix assembly; the cost of hanging is what makes this worth raising.
- A push/PR-triggered workflow with no `concurrency` group, queuing redundant
  runs on the same ref.
- `|| true` or `continue-on-error` hiding a failure that should surface —
  **only** when nothing nearby states why it is ignored. This repository uses
  `|| true` deliberately for diagnostics and for measurements that are not
  gates, and says so in an adjacent comment or step name. A stated rationale
  means the swallow is intended; absence of one is the finding.
- A container image referenced by `latest`.

**Repository conventions**

- A new heavy job that does not honour the `skip_all` / `skip_<workflow>`
  triage gate, so it cannot be paused during a review loop.

### 3. `.github/` configuration

- An issue template missing `name`, `description`, or `body`.
- A body input with an invalid `type` (valid: `dropdown`, `input`, `textarea`,
  `checkboxes`, `markdown`).
- A `dropdown` with an empty `options` list.
- A form input with no `id`, so nothing can parse it programmatically.
- `release.yml` referencing category labels that do not exist, or lacking a
  catch-all `*` category, which silently drops PRs from release notes.

### 4. YAML

- Spelling errors in YAML **keys** — a mistyped key is silently ignored rather
  than rejected. Ignore the content of values.

### 5. Repository rules nothing enforces

From `AGENTS.md` → "Critical Rules". No linter checks these:

- **Golden-file redaction** — an ARN, IP, account id, or access key reaching a
  committed golden plan. Always verify redaction.
- **`kubectl create`** used without the documented dry-run + apply pattern, so
  the step is not idempotent.
- **Skip labels created by hand** — they are auto-created by
  `internal-triage-skip` with colour `#1D76DB`.
- **`.target-branch`** left stale when branching strategy changes.
- **Raw commands** inlined where a `just` recipe exists, letting CI and local
  runs drift.

## Output

One line per finding:

```
<file>:L<line>: <check>: <problem>. <fix>.
```

Group by severity, worst first:

- **BLOCKING** — a secret, a permission grant, or a correctness defect that
  ships.
- **SHOULD-FIX** — reliability and reproducibility; the diff is safe but worse
  than it should be.
- **NIT** — everything else.

End with the verdict:

- `clean` — nothing actionable.
- `<n> finding(s)` — grouped as above.

Report findings. Do **not** apply them unless the caller asked for fixes.

## Anti-patterns

- **Don't** report anything in [What the gates already own](#what-the-gates-already-own).
- **Don't** escalate a medium/low zizmor pattern to BLOCKING — the threshold is
  a deliberate, documented choice.
- **Don't** demand production hardening from a demo; do report an insecure
  default a reader would copy.
- **Don't** review maintainability here.
- **Don't** infer cloud-account or runtime state the diff cannot show.
- **Don't** treat an empty report as a failure to try harder.

## If these rules earn their keep

The rules above are a snapshot, hand-carried. Upstream maintains 51 rulesets
and refreshes them; this file will drift.

If the lens proves its worth, the next step is the `ocr` CLI in **delegation
mode** — `ocr delegate preview` and `ocr delegate rule` resolve the maintained
upstream corpus plus a repository-local `.opencodereview/rule.json`, while the
agent still performs the review with its own model. No API key and no LLM spend
on the OCR side. That is a deliberate follow-up, not a prerequisite: it adds a
binary dependency, and its npm launcher self-updates unless `OCR_NO_UPDATE=1`
is set, so it needs its own decision.

## References

- [review-loop](../review-loop/SKILL.md) — the PR loop that calls this at step 2.
- [code-quality-review](../code-quality-review/SKILL.md) — the maintainability half of the same step.
- [ci-feedback-loop](../ci-feedback-loop/SKILL.md) — CI status/logs/artifacts.
- `AGENTS.md` → "Critical Rules" — the obligations in section 5.
- `.github/zizmor.yml`, `.lint/tflint/.tflint.hcl`, `.lint/trivy/trivy-scan.sh` — the gate configuration this skill defers to.
- Upstream: [alibaba/open-code-review](https://github.com/alibaba/open-code-review) (Apache-2.0), see [NOTICE](./NOTICE).
