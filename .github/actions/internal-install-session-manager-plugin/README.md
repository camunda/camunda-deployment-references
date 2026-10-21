# Install session-manager-plugin

## Description

Installs the AWS Session Manager plugin on an Ubuntu runner.

ECS Exec (`aws ecs execute-command`) needs it. The ECS dual-region
procedure scripts reach the Zeebe management API on port 9600 that way,
because terraform/infra/lb.tf gives that ALB listener a fixed-response
default and no forward rule — the API is deliberately not exposed.


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-install-session-manager-plugin@main
```
