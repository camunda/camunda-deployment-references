# Internal Report CI Event to Google Sheet

## Description

Append a single CI event (a failure "alert" or a non-blocking "warning")
as a row to a Google Sheet used for cross-branch reporting and triage.

Credentials are a Google service-account key pulled from HashiCorp Vault
(`GOOGLE_SHEETS_SA_KEY`). The service account must have Editor access to the
target spreadsheet.

The append is best-effort: a reporting error is surfaced as a `::warning::`
and never fails the calling job (unless `strict` is set to `true`). The row
column order matches the `events` tab header created by the bootstrap
script in this action directory.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `vault-addr` | <p>HashiCorp Vault address.</p> | `true` | `""` |
| `vault-role-id` | <p>Vault AppRole role id.</p> | `true` | `""` |
| `vault-secret-id` | <p>Vault AppRole secret id.</p> | `true` | `""` |
| `spreadsheet-id` | <p>Target Google spreadsheet id.</p> | `true` | `""` |
| `tab` | <p>Worksheet (tab) name to append to.</p> | `false` | `events` |
| `event-type` | <p>Event type, typically <code>failure</code> or <code>warning</code>.</p> | `true` | `""` |
| `category` | <p>Free-form category (e.g. <code>test-failure</code>, <code>infra-failure</code>, <code>helm-deprecation</code>, <code>helm-unknown-keys</code>).</p> | `false` | `""` |
| `severity` | <p>Optional severity label (<code>info</code>, <code>warning</code>, <code>critical</code>).</p> | `false` | `""` |
| `title` | <p>Short human-readable title / message for the event.</p> | `false` | `""` |
| `branch` | <p>Branch the event relates to (e.g. <code>stable/8.9</code>).</p> | `false` | `""` |
| `workflow-name` | <p>Workflow name the event relates to.</p> | `false` | `""` |
| `run-id` | <p>GitHub Actions run id of the observed run.</p> | `false` | `""` |
| `run-url` | <p>URL of the observed run.</p> | `false` | `""` |
| `commit-sha` | <p>Commit SHA of the observed run.</p> | `false` | `""` |
| `actor` | <p>Actor that triggered the observed run.</p> | `false` | `""` |
| `consecutive-failures` | <p>Optional consecutive-failure count, when known.</p> | `false` | `""` |
| `slack-ts` | <p>Optional Slack message timestamp to cross-link the alert.</p> | `false` | `""` |
| `strict` | <p>When <code>true</code>, a reporting error fails the step. Defaults to <code>false</code> so reporting never blocks the observed pipeline.</p> | `false` | `false` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-report-event-to-sheet@main
  with:
    vault-addr:
    # HashiCorp Vault address.
    #
    # Required: true
    # Default: ""

    vault-role-id:
    # Vault AppRole role id.
    #
    # Required: true
    # Default: ""

    vault-secret-id:
    # Vault AppRole secret id.
    #
    # Required: true
    # Default: ""

    spreadsheet-id:
    # Target Google spreadsheet id.
    #
    # Required: true
    # Default: ""

    tab:
    # Worksheet (tab) name to append to.
    #
    # Required: false
    # Default: events

    event-type:
    # Event type, typically `failure` or `warning`.
    #
    # Required: true
    # Default: ""

    category:
    # Free-form category (e.g. `test-failure`, `infra-failure`,
    # `helm-deprecation`, `helm-unknown-keys`).
    #
    # Required: false
    # Default: ""

    severity:
    # Optional severity label (`info`, `warning`, `critical`).
    #
    # Required: false
    # Default: ""

    title:
    # Short human-readable title / message for the event.
    #
    # Required: false
    # Default: ""

    branch:
    # Branch the event relates to (e.g. `stable/8.9`).
    #
    # Required: false
    # Default: ""

    workflow-name:
    # Workflow name the event relates to.
    #
    # Required: false
    # Default: ""

    run-id:
    # GitHub Actions run id of the observed run.
    #
    # Required: false
    # Default: ""

    run-url:
    # URL of the observed run.
    #
    # Required: false
    # Default: ""

    commit-sha:
    # Commit SHA of the observed run.
    #
    # Required: false
    # Default: ""

    actor:
    # Actor that triggered the observed run.
    #
    # Required: false
    # Default: ""

    consecutive-failures:
    # Optional consecutive-failure count, when known.
    #
    # Required: false
    # Default: ""

    slack-ts:
    # Optional Slack message timestamp to cross-link the alert.
    #
    # Required: false
    # Default: ""

    strict:
    # When `true`, a reporting error fails the step. Defaults to `false`
    # so reporting never blocks the observed pipeline.
    #
    # Required: false
    # Default: false
```
