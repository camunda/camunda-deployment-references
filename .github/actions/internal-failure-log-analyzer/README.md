# Internal — Failure log analyzer

## Description

DRAFT / PUBLIC PREVIEW — Fetches the failed-step logs of a GitHub Actions run
and asks a GitHub Models model to produce a concise root-cause analysis.

This mirrors `camunda/infraex-common-config`'s `gha-failure-log-analyzer`, but
returns the analysis as an output (`response`) instead of posting to Slack so
the caller can reuse it in several places — embed it in the auto-created
issue, hand it to the coding agent as a head start, and thread it onto the
Slack alert.

The model runs through `actions/ai-inference` (GitHub Models), so the caller's
job needs `models: read` and must pass a token entitled to it (the workflow
`GITHUB_TOKEN` is enough). No external AI service credential is required here:
the coding agent's own key (Anthropic) is unrelated to this analysis step.

GitHub Models does not host Anthropic Opus, so the default is the strongest
available code model (`openai/gpt-5`); override `model` as the catalog evolves.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `run-url` | <p>html_url of the failed workflow run to analyze.</p> | `true` | `""` |
| `gh-token` | <p>Token used both to download the run logs (needs <code>actions: read</code> on the run's repository) and to call GitHub Models (needs <code>models: read</code>).</p> | `true` | `""` |
| `model` | <p>GitHub Models model id used for the analysis. Defaults to the strongest available code model since Opus is not offered on GitHub Models.</p> | `false` | `openai/gpt-5` |
| `max-tokens` | <p>Maximum tokens for the model response.</p> | `false` | `800` |


## Outputs

| name | description |
| --- | --- |
| `response` | <p>The model's root-cause analysis (empty string when analysis could not run).</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-failure-log-analyzer@main
  with:
    run-url:
    # html_url of the failed workflow run to analyze.
    #
    # Required: true
    # Default: ""

    gh-token:
    # Token used both to download the run logs (needs `actions: read` on the run's repository) and to call GitHub Models (needs `models: read`).
    #
    # Required: true
    # Default: ""

    model:
    # GitHub Models model id used for the analysis. Defaults to the strongest available code model since Opus is not offered on GitHub Models.
    #
    # Required: false
    # Default: openai/gpt-5

    max-tokens:
    # Maximum tokens for the model response.
    #
    # Required: false
    # Default: 800
```
