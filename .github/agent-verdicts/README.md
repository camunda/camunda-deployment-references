# Agent verdicts

Coding agents dispatched by the
[`internal-failure-to-agent-fix`](../actions/internal-failure-to-agent-fix)
action write their CI-failure verdict to a single tracked file in this
directory, named `issue-<issue-number>.md`. A commit on the agent's own branch
is the only delivery channel its sandbox token is guaranteed to control (it
cannot reliably comment on issues or edit the PR description), and a file here
shows up in the PR diff for a human reviewer.
