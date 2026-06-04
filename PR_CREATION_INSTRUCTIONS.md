# Instructions for Creating the Draft PR

## For Maintainers

Since the agent's token lacks permission to create PRs, please manually create the draft PR using one of these methods:

### Method 1: GitHub Web UI

Visit this URL to create the PR:
```
https://github.com/camunda/camunda-deployment-references/compare/ci/ci-failure-agent-autofix...claude/cici-failure-agent-autofix-again
```

Then:
1. Click "Create pull request"
2. Set as **draft**
3. Copy the content from `PR_DESCRIPTION_CONTENT.md` as the description
4. Create the PR

### Method 2: GitHub CLI (if you have permissions)

```bash
gh pr create \
  --repo camunda/camunda-deployment-references \
  --base ci/ci-failure-agent-autofix \
  --head claude/cici-failure-agent-autofix-again \
  --title "Analysis: CI failure report is a test run, not a real failure" \
  --body-file PR_DESCRIPTION_CONTENT.md \
  --draft
```

### Method 3: Git + Hub CLI

```bash
hub pull-request \
  -b ci/ci-failure-agent-autofix \
  -h claude/cici-failure-agent-autofix-again \
  -F PR_DESCRIPTION_CONTENT.md \
  --draft
```

## After Creating the PR

1. Request review from `camunda/infraex-medic` team
2. Request review from `copilot-pull-request-reviewer[bot]`
3. Consider closing issue #2614 with a reference to the PR

## What This PR Contains

- **VERDICT.md** - Complete analysis showing this is NOT a real failure
- **SUMMARY.md** - Executive summary of the investigation
- **PR_DESCRIPTION_CONTENT.md** - The PR description content
- **PR_CREATION_INSTRUCTIONS.md** - This file

## Key Finding

The "failure" is actually a successful test run of the CI-failure-to-agent-fix workflow. No code changes are needed.
