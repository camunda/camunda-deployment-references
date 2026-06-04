# Internal — Workflow failure to agent fix

## Description

DRAFT / PUBLIC PREVIEW — Opens (or de-duplicates) a GitHub issue describing a
failed CI run and hands it to a coding agent so a fix is drafted automatically
as a pull request. Two interchangeable backends are supported:

- `claude`  (default): runs the official `anthropics/claude-code-action` inside
  this workflow. It authenticates with the GitHub App installation token passed
  via `github-token` (no human PAT) plus an `anthropic-api-key` service
  credential, and pins the model with `model`. Claude opens a draft PR itself.
- `copilot`: assigns the issue to the GitHub Copilot coding agent, which works
  asynchronously and opens its own draft PR. The Copilot assignment APIs reject
  server-to-server tokens, so this backend additionally requires a USER-to-server
  token (`copilot-token`). Prefer `claude` to avoid distributing a human PAT.

Human review stays mandatory for both backends: the PR is opened in draft, its
workflow runs require maintainer approval, and it still goes through the normal
review + CI gates before merge. This action only bootstraps the loop and never
merges anything.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `agent` | <p>Backend to use: "claude" or "copilot".</p> | `false` | `claude` |
| `model` | <p>Model the agent should use. For <code>claude</code> this is the Anthropic model id passed to <code>--model</code> (e.g. an Opus 4.x id). For <code>copilot</code> it is the optional Copilot model identifier passed to the assignment API.</p> | `false` | `""` |
| `github-token` | <p>Token with <code>issues: write</code> used for search/create/comment and, for the <code>claude</code> backend, handed to Claude to push its branch and open the PR. A GitHub App installation token (from Vault) is recommended — no human PAT needed.</p> | `true` | `""` |
| `anthropic-api-key` | <p>Anthropic API key (required for the <code>claude</code> backend).</p> | `false` | `""` |
| `copilot-token` | <p>User-to-server token allowed to assign the Copilot coding agent (required for the <code>copilot</code> backend). Leave empty for <code>claude</code>.</p> | `false` | `""` |
| `workflow-name` | <p>Display name of the failed workflow.</p> | `true` | `""` |
| `run-url` | <p>html_url of the failed workflow run.</p> | `true` | `""` |
| `run-id` | <p>Numeric id of the failed workflow run.</p> | `true` | `""` |
| `head-branch` | <p>Branch the failed run was executed on.</p> | `true` | `""` |
| `head-sha` | <p>Commit SHA the failed run was executed on.</p> | `true` | `""` |
| `base-ref` | <p>Branch the agent should base its fix branch on.</p> | `false` | `${{ github.event.repository.default_branch }}` |
| `labels` | <p>Comma-separated labels to apply to the created issue.</p> | `false` | `ci-failure,automation` |
| `mention` | <p>Team/handle to ping when no agent could pick up the issue (e.g. "@org/infraex").</p> | `false` | `""` |
| `slack-bot-token` | <p>Slack bot token used to thread the created issue onto the original failure alert. Leave empty to disable Slack threading.</p> | `false` | `""` |
| `slack-channel-id` | <p>Slack channel id the failure alert was posted to (required when threading).</p> | `false` | `""` |
| `enable-log-analysis` | <p>When "true", fetch the failed run logs and run a GitHub Models analysis whose root-cause summary is embedded in the issue, handed to the agent and threaded onto the Slack alert. Set "false" to skip the AI analysis.</p> | `false` | `true` |
| `models-token` | <p>Token entitled to GitHub Models (<code>models: read</code>) and to read the run logs (<code>actions: read</code>). The workflow <code>GITHUB_TOKEN</code> is enough. Required only when <code>enable-log-analysis</code> is "true".</p> | `false` | `""` |
| `analyzer-model` | <p>GitHub Models model id used for the failure analysis. Defaults to the strongest available code model (Opus is not offered on GitHub Models).</p> | `false` | `openai/gpt-4o` |
| `analyzer-max-tokens` | <p>Maximum tokens for the analysis model response.</p> | `false` | `800` |
| `group-across-branches` | <p>When "true" (default), failures of the same workflow are treated as one failure class and collapse into a single issue regardless of the branch they happened on: subsequent branches are grouped with a comment instead of opening a new issue. Set "false" to keep one issue per workflow+branch.</p> | `false` | `true` |
| `classification-key` | <p>Optional explicit signature used to classify/group failures. When set, failures sharing this key collapse into the same issue (use it to group by a job name or an error fingerprint rather than the workflow name). Defaults to the workflow name.</p> | `false` | `""` |
| `notify-bot-on-group` | <p>When "true" (default), a grouping comment @-mentions the coding-agent bot so it is notified of the new occurrence and can re-evaluate the issue.</p> | `false` | `true` |
| `bot-handle` | <p>Handle mentioned to re-engage the coding agent when a new occurrence is grouped onto an existing issue. Defaults to "@copilot" for the copilot backend and "@claude" for the claude backend.</p> | `false` | `""` |


## Outputs

| name | description |
| --- | --- |
| `issue-number` | <p>Number of the created (or already existing) issue.</p> |
| `issue-url` | <p>URL of the created (or already existing) issue.</p> |
| `agent-dispatched` | <p>"true" when an agent was handed the issue.</p> |
| `grouped` | <p>"true" when the failure was grouped onto an existing issue instead of opening a new one.</p> |
| `analysis` | <p>Root-cause analysis produced for the failure ('' when disabled or unavailable).</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-failure-to-agent-fix@main
  with:
    agent:
    # Backend to use: "claude" or "copilot".
    #
    # Required: false
    # Default: claude

    model:
    # Model the agent should use. For `claude` this is the Anthropic model id passed to `--model` (e.g. an Opus 4.x id). For `copilot` it is the optional Copilot model identifier passed to the assignment API.
    #
    # Required: false
    # Default: ""

    github-token:
    # Token with `issues: write` used for search/create/comment and, for the `claude` backend, handed to Claude to push its branch and open the PR. A GitHub App installation token (from Vault) is recommended — no human PAT needed.
    #
    # Required: true
    # Default: ""

    anthropic-api-key:
    # Anthropic API key (required for the `claude` backend).
    #
    # Required: false
    # Default: ""

    copilot-token:
    # User-to-server token allowed to assign the Copilot coding agent (required for the `copilot` backend). Leave empty for `claude`.
    #
    # Required: false
    # Default: ""

    workflow-name:
    # Display name of the failed workflow.
    #
    # Required: true
    # Default: ""

    run-url:
    # html_url of the failed workflow run.
    #
    # Required: true
    # Default: ""

    run-id:
    # Numeric id of the failed workflow run.
    #
    # Required: true
    # Default: ""

    head-branch:
    # Branch the failed run was executed on.
    #
    # Required: true
    # Default: ""

    head-sha:
    # Commit SHA the failed run was executed on.
    #
    # Required: true
    # Default: ""

    base-ref:
    # Branch the agent should base its fix branch on.
    #
    # Required: false
    # Default: ${{ github.event.repository.default_branch }}

    labels:
    # Comma-separated labels to apply to the created issue.
    #
    # Required: false
    # Default: ci-failure,automation

    mention:
    # Team/handle to ping when no agent could pick up the issue (e.g. "@org/infraex").
    #
    # Required: false
    # Default: ""

    slack-bot-token:
    # Slack bot token used to thread the created issue onto the original failure alert. Leave empty to disable Slack threading.
    #
    # Required: false
    # Default: ""

    slack-channel-id:
    # Slack channel id the failure alert was posted to (required when threading).
    #
    # Required: false
    # Default: ""

    enable-log-analysis:
    # When "true", fetch the failed run logs and run a GitHub Models analysis whose root-cause summary is embedded in the issue, handed to the agent and threaded onto the Slack alert. Set "false" to skip the AI analysis.
    #
    # Required: false
    # Default: true

    models-token:
    # Token entitled to GitHub Models (`models: read`) and to read the run logs (`actions: read`). The workflow `GITHUB_TOKEN` is enough. Required only when `enable-log-analysis` is "true".
    #
    # Required: false
    # Default: ""

    analyzer-model:
    # GitHub Models model id used for the failure analysis. Defaults to the strongest available code model (Opus is not offered on GitHub Models).
    #
    # Required: false
    # Default: openai/gpt-4o

    analyzer-max-tokens:
    # Maximum tokens for the analysis model response.
    #
    # Required: false
    # Default: 800

    group-across-branches:
    # When "true" (default), failures of the same workflow are treated as one failure class and collapse into a single issue regardless of the branch they happened on: subsequent branches are grouped with a comment instead of opening a new issue. Set "false" to keep one issue per workflow+branch.
    #
    # Required: false
    # Default: true

    classification-key:
    # Optional explicit signature used to classify/group failures. When set, failures sharing this key collapse into the same issue (use it to group by a job name or an error fingerprint rather than the workflow name). Defaults to the workflow name.
    #
    # Required: false
    # Default: ""

    notify-bot-on-group:
    # When "true" (default), a grouping comment @-mentions the coding-agent bot so it is notified of the new occurrence and can re-evaluate the issue.
    #
    # Required: false
    # Default: true

    bot-handle:
    # Handle mentioned to re-engage the coding agent when a new occurrence is grouped onto an existing issue. Defaults to "@copilot" for the copilot backend and "@claude" for the claude backend.
    #
    # Required: false
    # Default: ""
```
