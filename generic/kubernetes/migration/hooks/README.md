# Migration Hooks

Place shell scripts in this directory to run custom logic before or after each migration phase.

## Naming Convention

Scripts must be named `<hook-point>.sh` and be executable:

| Hook Point | Trigger |
|---|---|
| `pre-phase-1.sh` | Before deploying target infrastructure |
| `post-phase-1.sh` | After target infrastructure is deployed |
| `pre-phase-2.sh` | Before initial backup |
| `post-phase-2.sh` | After initial backup |
| `pre-phase-3.sh` | Before cutover (before freeze) |
| `post-phase-3.sh` | After cutover is complete |
| `pre-phase-4.sh` | Before validation |
| `post-phase-4.sh` | After validation |
| `pre-rollback.sh` | Before rollback |
| `post-rollback.sh` | After rollback |

## Example

```bash
#!/bin/bash
# hooks/pre-phase-3.sh — Send a Slack notification before cutover

curl -X POST "$SLACK_WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d '{"text":"⚠️ Camunda migration cutover starting — downtime expected"}'
```

## Notes

- Hook scripts are `source`d (not forked), so they have access to all library functions and variables.
- A failing hook will abort the migration (due to `set -e`). To make a hook best-effort, add `|| true`.
- Only `.sh` files matching the exact hook point name are executed.
