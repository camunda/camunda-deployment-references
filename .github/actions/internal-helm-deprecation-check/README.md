# Internal Helm Deprecation Check

## Description

Check for deprecation warnings and errors in the deployed Camunda Helm chart.
Uses `helm get notes` to retrieve the release notes and scans for
`[camunda][warning]` (deprecated configuration) and `[camunda][error]`
(removed configuration) messages.
Optionally validates that deployed values do not contain unknown keys
by checking against a strict version of the chart's JSON Schema.

Findings are reported in an event-aware, non-blocking way:
  - pull_request / pull_request_target / workflow_run: posted to a
    single shared PR comment (one comment per PR, one section per
    workflow/job/release/namespace combination).
  - schedule: emitted as ::warning:: annotations and, when the Slack
    inputs are wired, posted to Slack via the shared
    report-failure-on-slack action.
  - workflow_dispatch / push / any other event: emitted as
    ::warning:: annotations in the job log only.
The workflow is NEVER failed by this action; the intent is to trace
drift, not to block release pipelines.

See: https://github.com/camunda/camunda-platform-helm/issues/4564


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `release-name` | <p>The Helm release name to check</p> | `false` | `camunda` |
| `namespace` | <p>The Kubernetes namespace where the release is deployed</p> | `false` | `camunda` |
| `kube-context` | <p>The Kubernetes context to use (optional, defaults to current context)</p> | `false` | `""` |
| `exclude-patterns` | <p>Newline-separated list of fixed strings to exclude from warnings and errors. Messages containing any of these strings will be ignored.</p> | `false` | `""` |
| `check-unknown-keys` | <p>When set to 'true', deployed values are validated against a strict version of the chart's JSON Schema to detect unknown keys (typos, removed properties). The schema is automatically extracted from the deployed chart. See: https://github.com/camunda/camunda-platform-helm/issues/4564</p> | `false` | `true` |
| `comment-section-key` | <p>Optional extra identifier mixed into the PR comment section ID. Use this when the same workflow + job + release-name + namespace tuple runs more than once (e.g. across matrix entries) and each run should produce its own section in the shared PR comment.</p> | `false` | `""` |
| `github-token` | <p>Token used to read and update the shared PR comment. Defaults to the workflow-provided GITHUB_TOKEN. The token needs <code>pull-requests: write</code> permission for the comment to be posted.</p> | `false` | `${{ github.token }}` |
| `vault-addr` | <p>HashiCorp Vault address. Required only when posting a Slack alert on scheduled runs. Pass <code>${{ secrets.VAULT_ADDR }}</code>.</p> | `false` | `""` |
| `vault-role-id` | <p>HashiCorp Vault AppRole role id. Required only when posting a Slack alert on scheduled runs. Pass <code>${{ secrets.VAULT_ROLE_ID }}</code>.</p> | `false` | `""` |
| `vault-secret-id` | <p>HashiCorp Vault AppRole secret id. Required only when posting a Slack alert on scheduled runs. Pass <code>${{ secrets.VAULT_SECRET_ID }}</code>.</p> | `false` | `""` |
| `slack-channel-id` | <p>Slack channel id to alert when findings are detected on a scheduled run. When empty (default), no Slack notification is posted; findings are still logged as <code>::warning::</code> annotations.</p> | `false` | `""` |
| `slack-mention-people` | <p>Slack handles or group mentions to include in the scheduled-run alert (e.g. <code>@infraex-medic</code>). Only used when <code>slack-channel-id</code> is set and the event is <code>schedule</code>.</p> | `false` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-helm-deprecation-check@main
  with:
    release-name:
    # The Helm release name to check
    #
    # Required: false
    # Default: camunda

    namespace:
    # The Kubernetes namespace where the release is deployed
    #
    # Required: false
    # Default: camunda

    kube-context:
    # The Kubernetes context to use (optional, defaults to current context)
    #
    # Required: false
    # Default: ""

    exclude-patterns:
    # Newline-separated list of fixed strings to exclude from warnings and errors.
    # Messages containing any of these strings will be ignored.
    #
    # Required: false
    # Default: ""

    check-unknown-keys:
    # When set to 'true', deployed values are validated against a strict
    # version of the chart's JSON Schema to detect unknown keys
    # (typos, removed properties).
    # The schema is automatically extracted from the deployed chart.
    # See: https://github.com/camunda/camunda-platform-helm/issues/4564
    #
    # Required: false
    # Default: true

    comment-section-key:
    # Optional extra identifier mixed into the PR comment section ID.
    # Use this when the same workflow + job + release-name + namespace
    # tuple runs more than once (e.g. across matrix entries) and each
    # run should produce its own section in the shared PR comment.
    #
    # Required: false
    # Default: ""

    github-token:
    # Token used to read and update the shared PR comment.
    # Defaults to the workflow-provided GITHUB_TOKEN. The token needs
    # `pull-requests: write` permission for the comment to be posted.
    #
    # Required: false
    # Default: ${{ github.token }}

    vault-addr:
    # HashiCorp Vault address. Required only when posting a Slack
    # alert on scheduled runs. Pass `${{ secrets.VAULT_ADDR }}`.
    #
    # Required: false
    # Default: ""

    vault-role-id:
    # HashiCorp Vault AppRole role id. Required only when posting a
    # Slack alert on scheduled runs. Pass `${{ secrets.VAULT_ROLE_ID }}`.
    #
    # Required: false
    # Default: ""

    vault-secret-id:
    # HashiCorp Vault AppRole secret id. Required only when posting a
    # Slack alert on scheduled runs. Pass `${{ secrets.VAULT_SECRET_ID }}`.
    #
    # Required: false
    # Default: ""

    slack-channel-id:
    # Slack channel id to alert when findings are detected on a
    # scheduled run. When empty (default), no Slack notification is
    # posted; findings are still logged as `::warning::` annotations.
    #
    # Required: false
    # Default: ""

    slack-mention-people:
    # Slack handles or group mentions to include in the scheduled-run
    # alert (e.g. `@infraex-medic`). Only used when `slack-channel-id`
    # is set and the event is `schedule`.
    #
    # Required: false
    # Default: ""
```
