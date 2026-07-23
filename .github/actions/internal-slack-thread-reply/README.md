# Internal — Slack thread reply

## Description

DRAFT / PUBLIC PREVIEW — Posts a reply into an existing Slack alert thread.

The repository's failure alerts are posted by `report-failure-on-slack`
(camunda/infraex-common-config) directly inside each test workflow, so the
parent message `ts` is not available to the decoupled `workflow_run` watcher.
This action bridges that gap: given the failed run URL (which the alert text
contains), it locates the parent alert in the channel history and replies in
its thread. Callers that already know the `thread-ts` (e.g. a resolution
handler reading it back from the issue) can pass it directly to skip the
lookup.

Used to thread the auto-created CI-failure issue — and later its resolution —
onto the original Slack alert, so a reader sees what failed and whether it was
fixed without leaving the thread.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `slack-bot-token` | <p>Slack bot token with <code>conversations.history</code> (lookup) and <code>chat:write</code> (reply) scopes.</p> | `true` | `""` |
| `channel-id` | <p>Slack channel id the alert was posted to.</p> | `true` | `""` |
| `message` | <p>Markdown text of the reply to post in the thread.</p> | `true` | `""` |
| `thread-ts` | <p>Parent message timestamp to reply to. When empty, the action looks it up by searching recent channel history for <code>match-text</code>.</p> | `false` | `""` |
| `match-text` | <p>Substring used to locate the parent message when <code>thread-ts</code> is empty (typically the failed run URL, which the alert text contains).</p> | `false` | `""` |
| `history-limit` | <p>How many recent channel messages to scan when looking up the thread.</p> | `false` | `200` |


## Outputs

| name | description |
| --- | --- |
| `thread-ts` | <p>Timestamp of the parent message the reply was threaded onto ('' if not found).</p> |
| `posted` | <p>"true" when a message was posted to Slack.</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-slack-thread-reply@main
  with:
    slack-bot-token:
    # Slack bot token with `conversations.history` (lookup) and `chat:write` (reply) scopes.
    #
    # Required: true
    # Default: ""

    channel-id:
    # Slack channel id the alert was posted to.
    #
    # Required: true
    # Default: ""

    message:
    # Markdown text of the reply to post in the thread.
    #
    # Required: true
    # Default: ""

    thread-ts:
    # Parent message timestamp to reply to. When empty, the action looks it up by searching recent channel history for `match-text`.
    #
    # Required: false
    # Default: ""

    match-text:
    # Substring used to locate the parent message when `thread-ts` is empty (typically the failed run URL, which the alert text contains).
    #
    # Required: false
    # Default: ""

    history-limit:
    # How many recent channel messages to scan when looking up the thread.
    #
    # Required: false
    # Default: 200
```
