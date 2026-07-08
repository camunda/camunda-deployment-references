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
  - schedule (real or simulated via a `schedules/*` head_ref): emitted
    as ::warning:: annotations and, when the Slack inputs are wired,
    posted to Slack via the shared report-warning-on-slack action
    (an advisory, non-failure notification).
    Simulated schedules are detected from the caller workflow's
    `IS_SCHEDULE` env var (set to `'true'` when
    `contains(github.head_ref, 'schedules/') || github.event_name == 'schedule'`).
  - workflow_dispatch / push / any other event: emitted as
    ::warning:: annotations in the job log only.
Findings (deprecation warnings, removed keys, unknown keys) are never
treated as failures — the intent is to trace drift, not to block release
pipelines. The action can still exit non-zero on genuine internal errors
(e.g. `helm get notes` / `helm get values` failures, or an internal error
in the unknown-keys validator).

See: https://github.com/camunda/camunda-platform-helm/issues/4564


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `release-name` | <p>The Helm release name to check</p> | `false` | `camunda` |
| `namespace` | <p>The Kubernetes namespace where the release is deployed</p> | `false` | `camunda` |
| `kube-context` | <p>The Kubernetes context to use (optional, defaults to current context)</p> | `false` | `""` |
| `exclude-patterns` | <p>Newline-separated list of fixed strings (one pattern per line) to exclude from warnings and errors. Messages containing any of these strings are ignored. Patterns are matched per line, so a space-separated value is treated as a single pattern, not several.</p> | `false` | `webModeler.restapi.mail.fromAddress webModeler.restapi.mail.fromName orchestration.exporters.camunda.enabled` |
| `check-unknown-keys` | <p>When set to 'true', deployed values are validated against a strict version of the chart's JSON Schema to detect unknown keys (typos, removed properties). The schema is automatically extracted from the deployed chart. See: https://github.com/camunda/camunda-platform-helm/issues/4564</p> | `false` | `true` |
| `comment-section-key` | <p>Optional extra identifier mixed into the PR comment section ID. Use this when the same workflow + job + release-name + namespace tuple runs more than once (e.g. across matrix entries) and each run should produce its own section in the shared PR comment.</p> | `false` | `""` |
| `github-token` | <p>Token used to read and update the shared PR comment. Defaults to the workflow-provided GITHUB_TOKEN. The token needs <code>pull-requests: write</code> permission for the comment to be posted.</p> | `false` | `${{ github.token }}` |
| `vault-addr` | <p>HashiCorp Vault address. Required only when posting a Slack alert on scheduled runs. Pass secrets.VAULT_ADDR from the caller.</p> | `false` | `""` |
| `vault-role-id` | <p>HashiCorp Vault AppRole role id. Required only when posting a Slack alert on scheduled runs. Pass secrets.VAULT<em>ROLE</em>ID from the caller.</p> | `false` | `""` |
| `vault-secret-id` | <p>HashiCorp Vault AppRole secret id. Required only when posting a Slack alert on scheduled runs. Pass secrets.VAULT<em>SECRET</em>ID from the caller.</p> | `false` | `""` |
| `slack-channel-id` | <p>Slack channel id to alert when findings are detected on a (real or simulated) scheduled run. When left empty, the action defaults to the standard infraex channels:</p> <ul> <li><code>C076N4G1162</code> (infraex-alerts) on real schedule events</li> <li><code>C07E4FF6YMB</code> (infraex-test)   on every other event (simulated schedules via <code>schedules/*</code> head<em>ref,  workflow</em>dispatch, etc.) Set explicitly to override.</li> </ul> | `false` | `""` |
| `slack-mention-people` | <p>Slack handles or group mentions to include in the scheduled-run alert (e.g. <code>@infraex-medic</code>). Only used when the caller workflow advertises <code>IS_SCHEDULE=true</code> (real or simulated schedule).</p> | `false` | `""` |


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
    # Newline-separated list of fixed strings (one pattern per line) to
    # exclude from warnings and errors. Messages containing any of these
    # strings are ignored. Patterns are matched per line, so a
    # space-separated value is treated as a single pattern, not several.
    #
    # Required: false
    # Default: webModeler.restapi.mail.fromAddress webModeler.restapi.mail.fromName orchestration.exporters.camunda.enabled

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
    # alert on scheduled runs. Pass secrets.VAULT_ADDR from the caller.
    #
    # Required: false
    # Default: ""

    vault-role-id:
    # HashiCorp Vault AppRole role id. Required only when posting a
    # Slack alert on scheduled runs. Pass secrets.VAULT_ROLE_ID from the caller.
    #
    # Required: false
    # Default: ""

    vault-secret-id:
    # HashiCorp Vault AppRole secret id. Required only when posting a
    # Slack alert on scheduled runs. Pass secrets.VAULT_SECRET_ID from the caller.
    #
    # Required: false
    # Default: ""

    slack-channel-id:
    # Slack channel id to alert when findings are detected on a
    # (real or simulated) scheduled run. When left empty, the
    # action defaults to the standard infraex channels:
    #   - `C076N4G1162` (infraex-alerts) on real schedule events
    #   - `C07E4FF6YMB` (infraex-test)   on every other event
    #     (simulated schedules via `schedules/*` head_ref,
    #      workflow_dispatch, etc.)
    # Set explicitly to override.
    #
    # Required: false
    # Default: ""

    slack-mention-people:
    # Slack handles or group mentions to include in the scheduled-run
    # alert (e.g. `@infraex-medic`). Only used when the caller
    # workflow advertises `IS_SCHEDULE=true` (real or simulated
    # schedule).
    #
    # Required: false
    # Default: ""
```
