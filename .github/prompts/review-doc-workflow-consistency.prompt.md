# Review: Documentation ↔ Workflow overlay consistency

## Purpose

Verify that Helm values overlay files referenced in documentation match those used in CI workflows — same files, same merge order, no missing overlays.

The documentation lives in a **separate repository**: [`camunda/camunda-docs`](https://github.com/camunda/camunda-docs).
The workflows and overlay files live in **this repository**: `camunda/camunda-deployment-references`.

## Prerequisites

Before running this review, clone the `camunda-docs` repo next to this one and checkout the relevant branch:

```bash
# From the parent directory of camunda-deployment-references
git clone https://github.com/camunda/camunda-docs.git camunda-docs
cd camunda-docs
git checkout <your-docs-branch>  # e.g., the branch from the docs PR
cd ..
```

Then open a **multi-root workspace** in VS Code containing both repos, or simply reference the
`camunda-docs/` path relative to this repo's parent directory.

> **Tip**: If both repos are side-by-side, you can open them together:
> `code camunda-deployment-references camunda-docs`

When the user invokes this prompt, they should specify:
- The **docs branch** (or PR) to check against
- Which doc ↔ workflow pair(s) to verify (or "all")

**If the docs branch is not specified, ask the user before proceeding.**

## When to use

Invoke this prompt during PR reviews when changes touch:
- **In `camunda-docs`**: `docs/self-managed/deployment/helm/cloud-providers/**/*.md`
- **In `camunda-deployment-references`**: `.github/workflows/*_tests.yml`, `generic/**/helm-values/*.yml`, `generic/kubernetes/operator-based/**/*.yml`

## Known doc ↔ workflow pairs

| Documentation (in `camunda/camunda-docs`) | CI Workflow (in `camunda/camunda-deployment-references`) |
|---|---|
| `docs/self-managed/deployment/helm/cloud-providers/openshift/redhat-openshift.md` | `.github/workflows/aws_openshift_rosa_hcp_single_region_tests.yml` |
| `docs/self-managed/deployment/helm/cloud-providers/openshift/dual-region.md` | `.github/workflows/aws_openshift_rosa_hcp_dual_region_tests.yml` |
| `docs/self-managed/deployment/helm/cloud-providers/amazon/amazon-eks/eks-helm.md` | `.github/workflows/aws_kubernetes_eks_single_region_tests.yml` |
| `docs/self-managed/deployment/helm/cloud-providers/azure/microsoft-aks/aks-helm.md` | `.github/workflows/azure_kubernetes_aks_single_region_tests.yml` |
| `docs/self-managed/deployment/helm/cloud-providers/kind.md` | `.github/workflows/local_kubernetes_kind_single_region_tests.yml` |

## Instructions

For each doc ↔ workflow pair affected by the PR(s) under review, perform these checks:

### 1. Extract overlay files from the documentation

Search for all `yq` merge commands in the doc file. For each one, extract:
- The overlay file path (e.g., `generic/openshift/single-region/helm-values/scc.yml`)
- The context/condition under which it's applied (e.g., "Routes tab", "Restrictive SCCs tab", "WebModeler enabled")
- Its position relative to other merges (order)

Also search for `yaml reference` blocks pointing to overlay files — these should have a corresponding `yq` merge command.

### 2. Extract overlay files from the workflow

Search for all `yq` and `cp -f` commands in the workflow's "Assemble deployment values" step. For each one, extract:
- The overlay file path
- The condition under which it's applied (e.g., `if domain`, `if WEBMODELER_ENABLED`)
- Its position in the merge sequence

### 3. Compare and report

Build a comparison table:

| Overlay file | In Doc? | In Workflow? | Same condition? | Order consistent? |
|---|---|---|---|---|

Flag any of the following issues:
- **Missing in workflow**: An overlay documented but never tested in CI → risk of silent breakage
- **Missing in doc**: An overlay used in CI but not documented → users won't know about it
- **Order mismatch**: Overlays applied in a different order. Only matters if they share keys (check for key conflicts using `yq keys`)
- **Condition mismatch**: An overlay applied unconditionally in one place but conditionally in the other

### 4. Check overlay file existence

Verify that every overlay file path referenced in both the doc and workflow actually exists in the repository. A renamed or deleted file would break both.

### 5. Known acceptable gaps

The following gaps are known and accepted — do not flag them:
- `no-scc.yml`: Documented but not tested (trivial file: sets `adaptSecurityContext: disabled` which is the chart default)
- Test-only overlays (e.g., `tests/helm-values/registry.yml`, `tests/helm-values/identity.yml`): Used in CI but not documented (test infrastructure, not user-facing)
- Identity secrets overlay (`camunda-values-identity-secrets.yml`): Test utility, not user-facing

## Output format

Summarize findings as:

```
## Doc ↔ Workflow Consistency Review

**Pair**: `<doc-file>` ↔ `<workflow-file>`
**Status**: ✅ Consistent | ⚠️ Issues found

### Issues (if any)
- [ ] <description of issue>

### Overlay comparison table
| Overlay | Doc | Workflow | Notes |
|---|---|---|---|
```
