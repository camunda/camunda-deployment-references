# AWS Fault Injection Service (FIS) — Chaos Tests

Scripts to run chaos experiments with [AWS Fault Injection Service (FIS)](https://docs.aws.amazon.com/fis/latest/userguide/what-is.html) against an Orchestration Cluster running on ECS Fargate.

They target any ECS deployment that follows the reference architecture in
[`aws/containers/ecs-single-region-fargate`](../../containers/ecs-single-region-fargate/README.md): the experiments find their targets by
ECS cluster name and service prefix, so nothing here is tied to a particular
account or environment. Every default is overridable, either with a flag or an
environment variable — see [Configuration](#configuration).

> [!WARNING]
> These experiments deliberately break a running cluster: they stop broker
> tasks, cut them off the network, and in one case isolate an entire
> Availability Zone. Run them against a disposable deployment, never against
> anything carrying data you want to keep.

## Overview

Five experiment types are supported:

### 1. Broker Stop

Stops a **random Camunda broker** (ECS task) using the FIS `aws:ecs:stop-task` action, causing the ECS service to launch a replacement. This tests the cluster's ability to recover from a broker crash/restart — the most common real-world failure mode. Includes automated pre/post health verification.

### 2. Broker Disconnect

Isolates the subnet the targeted broker runs in, using `aws:network:disrupt-connectivity`. The task keeps running but cannot reach the other brokers, which tests partition leadership failover while the disconnected broker is still alive. Includes automated pre/post health verification.

### 3. S3 Disconnect

Blocks **S3 traffic** from the targeted broker's subnet using `aws:network:disrupt-connectivity` with `scope=s3`. The broker can still reach the other brokers and Aurora, but not S3. Losing S3 should make `NodeIdProvider` shut the broker down once it can no longer renew its lease; the replacement task should acquire a node id and become healthy. Includes automated pre/post health verification.

### 4. S3 Disconnect + Broker Stop (compound failure)

Combines **two simultaneous faults** in a single FIS experiment:
1. **S3 disconnect** — blocks S3 traffic from one broker's subnet (same as experiment #3)
2. **Broker stop** — stops a different broker task via `aws:ecs:stop-task` (ECS replaces it)

Both actions run in parallel. The script selects two brokers in different AZs (when possible). This tests how the cluster handles a compound failure — one broker loses S3 while another crashes. Includes automated pre/post health verification with a 900s recovery timeout.

### 5. AZ Disconnect (broad impact)

Disconnects an **entire Availability Zone** by disrupting network connectivity on all private subnets in that AZ. This affects **all** benchmarks and services running in the AZ. Not recommended for production.

> [!IMPORTANT]
> **Experiments 2, 3 and 4 are subnet-scoped, not task-scoped.** FIS implements
> `aws:network:disrupt-connectivity` by swapping the network ACL of the target
> *subnet*, so the fault hits every task in that subnet, not only the broker the
> script selected and names in its output. The reference architecture places the
> Orchestration Cluster, Connectors, the load generator and Prometheus in the
> same private subnets, so a broker disconnect also cuts off whichever of those
> happen to run in the same AZ.
>
> This is a property of the FIS action, not of these scripts: AWS offers no
> per-ENI connectivity disruption. Read the result accordingly — a recovery time
> measured here includes collateral damage to co-located services. To isolate a
> single broker, give it a dedicated subnet.
>
> Only experiment 1 (broker stop) is genuinely single-task: `aws:ecs:stop-task`
> targets one task ARN.

### How network disruption works

When the experiment runs, FIS will:
1. **Clone** the network ACL associated with the target subnet(s)
2. **Add deny rules** to the cloned ACL that block intra-VPC traffic to/from subnets in other AZs
3. **Associate** the cloned ACL (tagged `managedByFIS=true`) with the target subnet(s)
4. After the duration expires, **restore** the original network ACL associations and **delete** the cloned ACLs

This effectively isolates the ECS tasks running in the target subnet(s) from tasks in other AZs.

### Experiment logging

All experiments are logged to CloudWatch Logs (log group: `/fis/chaos-tests` by default). This provides an audit trail of experiment actions, timing, and outcomes. Logs can be viewed in the AWS Console under CloudWatch > Log groups.

## Prerequisites

- AWS CLI v2 installed and configured
- `jq` installed (`sudo apt install jq` or `brew install jq`)
- AWS credentials with permission to create IAM roles and FIS experiments:
  ```bash
  aws sso login --profile <your-profile>
  ```
- An Orchestration Cluster already deployed on ECS Fargate (VPC, subnets and ECS cluster), for example through [`aws/containers/ecs-single-region-fargate`](../../containers/ecs-single-region-fargate/README.md)
- Pre/post verification queries the cluster topology over its management endpoint, so that endpoint has to be reachable from where you run the scripts

## Folder Structure

```
chaos-fis/
├── README.md                          # This file
├── setup/
│   ├── 01-setup-fis-experiment-role.sh  # Creates the IAM role that FIS assumes (one-time)
│   ├── 02-setup-fis-admin-role.sh       # Creates the FIS-Admin role for SSO users (one-time)
│   └── teardown.sh                      # Removes all IAM roles/policies (cleanup)
├── experiments/
│   ├── lib/
│   │   └── common.sh                   # Shared functions (ECS discovery, FIS helpers, health checks)
│   ├── assume-fis-role.sh               # Assumes FIS-Admin role (run before experiments)
│   ├── verify-cluster-health.sh         # Checks ECS service + Camunda cluster health via v2 topology API
│   ├── experiment-status.sh             # Checks FIS experiment status
│   ├── experiment-stop.sh               # Stops a running FIS experiment
│   ├── experiment-list.sh               # Lists all FIS experiment templates
│   ├── broker-stop/
│   │   ├── broker-stop-create.sh        # Creates a broker stop FIS template
│   │   └── broker-stop-run.sh           # Runs broker stop with health verification
│   ├── broker-disconnect/
│   │   ├── broker-disconnect-create.sh  # Creates a single-broker disconnect FIS template
│   │   └── broker-disconnect-run.sh     # Runs broker disconnect with health verification
│   ├── s3-disconnect/
│   │   ├── s3-disconnect-create.sh      # Creates an S3 disconnect FIS template for one broker
│   │   └── s3-disconnect-run.sh         # Runs S3 disconnect with health verification
│   ├── s3-disconnect-broker-stop/
│   │   ├── s3-disconnect-broker-stop-create.sh  # Creates compound FIS template (S3 disconnect + broker stop)
│   │   └── s3-disconnect-broker-stop-run.sh     # Runs compound experiment with health verification
│   └── az-disconnect/
│       ├── az-disconnect-create.sh      # Creates an AZ disconnect FIS template
│       └── az-disconnect-run.sh         # Starts an AZ disconnect FIS experiment
└── policies/
    ├── fis-experiment-role-trust.json    # Trust policy for the FIS experiment role
    ├── fis-experiment-role-perms.json    # Permissions for the FIS experiment role
    └── fis-admin-role-perms.json         # Permissions for the FIS-Admin role
```

## Quick Start

### One-time setup (run once per AWS account)

```bash
# 1. Create the IAM role that FIS assumes to perform network disruptions
./setup/01-setup-fis-experiment-role.sh

# 2. Create the FIS-Admin role that SSO users assume to manage experiments
./setup/02-setup-fis-admin-role.sh
```

### Running a broker stop experiment

This stops a random broker task, causing ECS to launch a replacement. Tests crash recovery.

```bash
# 1. Assume the FIS-Admin role (required before any FIS commands)
source ./experiments/assume-fis-role.sh

# 2. (Optional) Check cluster health before creating the experiment
./experiments/verify-cluster-health.sh --endpoint <ALB_DNS>

# 3. Create an experiment template targeting a single broker
#    A random broker is selected by default.
#    --prefix: the deployment prefix (e.g. camunda)
./experiments/broker-stop/broker-stop-create.sh --prefix camunda

# You can also target a broker in a specific AZ:
./experiments/broker-stop/broker-stop-create.sh --prefix camunda --az eu-west-2b

# 4. Run the experiment (includes pre/post health checks)
./experiments/broker-stop/broker-stop-run.sh --name broker-stop-camunda --endpoint <ALB_DNS> --prefix camunda

# The script will:
#   - Verify the cluster is healthy (pre-check)
#   - Run the FIS experiment (stops the broker task)
#   - Wait for ECS to launch a replacement
#   - Verify the cluster recovers (post-check, default 900s timeout)
#   - Print a summary report with PASS/FAIL result

# 5. (Optional) Stop early
./experiments/experiment-stop.sh --id <EXPERIMENT_ID>
```

### Running a broker disconnect experiment

This disconnects a single broker from a specific benchmark, with automated health verification.

```bash
# 1. Assume the FIS-Admin role (required before any FIS commands)
source ./experiments/assume-fis-role.sh

# 2. (Optional) Check cluster health before creating the experiment
./experiments/verify-cluster-health.sh --endpoint <ALB_DNS>

# 3. Create an experiment template targeting a single broker
#    A random broker is selected by default.
#    --prefix:  the deployment prefix (e.g. camunda)
#    --duration: how long the disruption lasts (ISO 8601, e.g., PT10M for 10 minutes)
./experiments/broker-disconnect/broker-disconnect-create.sh --prefix camunda --duration PT10M

# You can also target a broker in a specific AZ:
./experiments/broker-disconnect/broker-disconnect-create.sh --prefix camunda --az eu-west-2b --duration PT10M

# 4. Run the experiment (includes pre/post health checks)
./experiments/broker-disconnect/broker-disconnect-run.sh --name broker-disconnect-camunda --endpoint <ALB_DNS>

# The script will:
#   - Verify the cluster is healthy (pre-check)
#   - Run the experiment and wait for completion
#   - Verify the cluster recovers (post-check, default 120s timeout)
#   - Print a summary report with PASS/FAIL result

# 5. (Optional) Stop early
./experiments/experiment-stop.sh --id <EXPERIMENT_ID>
```

### Running an S3 disconnect experiment

This blocks S3 traffic from a single broker's subnet. The broker can still talk to other brokers and Aurora, but cannot reach S3.

```bash
# 1. Assume the FIS-Admin role (required before any FIS commands)
source ./experiments/assume-fis-role.sh

# 2. (Optional) Check cluster health before creating the experiment
./experiments/verify-cluster-health.sh --endpoint <ALB_DNS>

# 3. Create an experiment template targeting a single broker's S3 access
#    A random broker is selected by default.
#    --prefix:  the deployment prefix (e.g. camunda)
#    --duration: how long S3 is blocked (ISO 8601, e.g., PT10M for 10 minutes)
./experiments/s3-disconnect/s3-disconnect-create.sh --prefix camunda --duration PT10M

# You can also target a broker in a specific AZ:
./experiments/s3-disconnect/s3-disconnect-create.sh --prefix camunda --az eu-west-2b --duration PT10M

# 4. Run the experiment (includes pre/post health checks)
./experiments/s3-disconnect/s3-disconnect-run.sh --name s3-disconnect-camunda --endpoint <ALB_DNS>

# The script will:
#   - Verify the cluster is healthy (pre-check)
#   - Run the experiment (blocks S3 from the broker's subnet)
#   - Wait for experiment to complete
#   - Verify the cluster recovers (post-check, default 900s timeout)
#   - Print a summary report with PASS/FAIL result

# 5. (Optional) Stop early
./experiments/experiment-stop.sh --id <EXPERIMENT_ID>
```

### Running an S3 disconnect + broker stop experiment (compound failure)

This creates a compound failure scenario: S3 traffic is blocked from one broker's subnet while a different broker is simultaneously stopped. Both actions run **in parallel** to simulate overlapping failures.

```bash
# 1. Assume the FIS-Admin role (required before any FIS commands)
source ./experiments/assume-fis-role.sh

# 2. (Optional) Check cluster health before creating the experiment
./experiments/verify-cluster-health.sh --endpoint <ALB_DNS>

# 3. Create a compound experiment template
#    The script automatically picks two brokers (in different AZs if possible):
#    - Broker A's subnet gets S3 traffic blocked
#    - Broker B gets stopped via aws:ecs:stop-task
#    --prefix:   the deployment prefix (e.g. camunda)
#    --duration: how long the S3 disruption lasts (ISO 8601, e.g., PT10M)
./experiments/s3-disconnect-broker-stop/s3-disconnect-broker-stop-create.sh --prefix camunda --duration PT10M

# 4. Run the experiment (includes pre/post health checks)
./experiments/s3-disconnect-broker-stop/s3-disconnect-broker-stop-run.sh --name s3-disconnect-broker-stop-camunda --endpoint <ALB_DNS>

# The script will:
#   - Verify the cluster is healthy (pre-check)
#   - Run the experiment (both actions start in parallel)
#   - Wait for both actions to complete
#   - Verify the cluster recovers (post-check, default 900s timeout)
#   - Print a summary report showing per-action results

# 5. (Optional) Stop early
./experiments/experiment-stop.sh --id <EXPERIMENT_ID>
```

### Running an AZ disconnect experiment (broad impact)

This disconnects an entire AZ — use with caution as it affects all services in the AZ.

```bash
# 1. Assume the FIS-Admin role (required before any FIS commands)
source ./experiments/assume-fis-role.sh

# 2. Create an experiment template
./experiments/az-disconnect/az-disconnect-create.sh --az eu-west-2b --duration PT10M

# 3. Run the experiment
./experiments/az-disconnect/az-disconnect-run.sh --name 1-az-disconnect-dev

# 4. Monitor the experiment
./experiments/experiment-status.sh --id <EXPERIMENT_ID>

# 5. (Optional) Stop early
./experiments/experiment-stop.sh --id <EXPERIMENT_ID>
```

### Cluster health check (standalone)

You can check cluster health at any time:

```bash
# One-shot health check (topology only)
./experiments/verify-cluster-health.sh --endpoint <ALB_DNS>

# Include ECS service check (desired tasks == running tasks) before topology check
./experiments/verify-cluster-health.sh --endpoint <ALB_DNS> --prefix camunda

# Wait up to 120s for the cluster to become healthy
./experiments/verify-cluster-health.sh --endpoint <ALB_DNS> --prefix camunda --wait 120
```

### Return to SSO role

After you're done with FIS commands, unset the assumed role credentials:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

## Multi-user Support

`02-setup-fis-admin-role.sh` reads the role you are logged in as and writes it
into the `FIS-Admin` trust policy, so everyone who shares that role can assume
it with no per-user setup:

```bash
source ./experiments/assume-fis-role.sh
```

Run the setup as the role the team actually shares. Running it as a personal
role grants only that role, and running it again as a different one replaces
the trust policy rather than adding to it.

## Configuration

The experiment scripts read these environment variables; each one also has a
matching flag, and `--help` on any script lists the flags it accepts.

| Variable | Default | Description |
|---|---|---|
| `AWS_REGION` | `eu-west-2` | Region the experiments run in. One of the regions the account sweep covers — see [Cleanup](#cleanup). |
| `VPC_NAME` | `camunda-vpc` | VPC name tag used to find subnets (AZ disconnect) |
| `ECS_CLUSTER` | `camunda-cluster` | ECS cluster name, `<prefix>-cluster` in the reference architecture |
| `FIS_EXPERIMENT_ROLE` | `FIS-Experiment-Role` | IAM role FIS assumes |
| `FIS_ADMIN_ROLE` | `FIS-Admin` | IAM role team members assume |
| `FIS_LOG_GROUP` | `/fis/chaos-tests` | CloudWatch log group for experiment logs |

The `--prefix` every experiment takes is the reference architecture's
`var.prefix`, `camunda` by default. It is what the scripts match the
Orchestration Cluster's ECS service on, so passing anything else finds nothing.
The two `setup/` scripts take no region: IAM roles are global.

## Cleanup

```bash
./setup/teardown.sh                 # eu-west-2 by default
./setup/teardown.sh --region eu-west-3 --yes
```

It removes, in that order, the experiment templates tagged
`managed_by=chaos-tests`, the `/fis/chaos-tests` log group, and the two IAM
roles. The order matters: deleting a template needs `fis:DeleteExperimentTemplate`,
so removing the roles first would strand every template it left behind.

Running experiments are **not** stopped. Stop them with `experiment-stop.sh`
first, or the network disruption outlives the template that described it.

The script also reports any network ACL still tagged `managedByFIS=true`. FIS
restores the original association when an action ends, but an experiment killed
rather than stopped can leave its clone attached — and the deny rules with it.
Nothing else reclaims those, so a subnet stays cut off until someone looks.

### What the account sweep does and does not reclaim

The CI account is swept by
[`infraex-common-config`](https://github.com/camunda/infraex-common-config):
nightly per region, plus a weekly pass that deletes IAM roles. Two consequences
worth knowing before you rely on either:

- **The roles are not permanent.** `FIS-Admin` and `FIS-Experiment-Role` match
  none of the sweep's keep-patterns (`AWS*`, `AmazonEKS*`, `ManagedOpenShift*`,
  `ref-arch-*`, `Wiz*`, …), so the weekly pass deletes them and the next
  experiment fails with `AccessDenied`. Re-run the two setup scripts. If your
  account needs them to survive, name them with the `ref-arch-` prefix:
  `FIS_ADMIN_ROLE=ref-arch-fis-admin ./setup/02-setup-fis-admin-role.sh`.
- **Only the swept regions are covered.** The nightly sweep runs in
  `eu-west-2`, `eu-west-3` and `eu-central-2` daily, and in `eu-north-1`,
  `eu-south-1`, `us-east-1` and `us-east-2` on Saturdays. Anything these
  scripts leave in another region — templates, the log group, a leaked network
  ACL — stays there. That is why the default region is `eu-west-2`, which is
  also where the ECS reference architecture runs its own tests.

## Investigated but not implemented: EFS Disconnect

We investigated simulating EFS storage outage for a single broker using AWS FIS. The goal was to block NFS traffic (port 2049) between a broker's ECS task and its EFS mount target, so the broker loses access to its data directory (`/usr/local/camunda/data`) while remaining connected to other brokers, Aurora, and S3.

### What we tried

#### Approach 1: NACL-based disruption via `aws:network:disrupt-connectivity` with `scope=prefix-list`

We created a managed prefix list containing the EFS mount target IPs (as /32 CIDRs) and used the FIS `aws:network:disrupt-connectivity` action with `scope=prefix-list` to add NACL deny rules blocking traffic to those IPs.

**Why it didn't work:** The EFS mount targets are created in the **same private subnets** as the ECS broker tasks (see the orchestration-cluster module's `efs.tf`: `subnet_id = var.vpc_private_subnets[count.index]`). Network ACLs only filter traffic that crosses subnet boundaries. Traffic between two resources in the same subnet (broker → EFS mount target) never passes through the NACL and is therefore never blocked. The experiment executes without error, but the broker can still read and write to EFS.

#### Approach 2: Security group manipulation

We considered revoking the NFS ingress rule (port 2049) from the EFS security group via AWS CLI during the experiment, then restoring it afterward.

**Why we didn't proceed:** Directly manipulating security groups outside of Terraform introduces drift and risk. If the restore step fails (e.g., script crash, credential expiry), the security group would be left in a broken state, affecting all brokers — not just the targeted one. This approach was rejected as too fragile for a chaos testing tool.

#### Approach 3: FIS `aws:ecs:task-network-blackhole-port`

FIS offers `aws:ecs:task-network-blackhole-port`, which drops traffic for a specific port at the task level using iptables rules injected via the SSM agent. This would be the ideal approach — targeting port 2049 (NFS) egress on a specific broker task.

**Why we didn't proceed:** This action requires significant changes to the upstream ECS task definition in the `camunda/camunda-deployment-references` orchestration-cluster module:

- `pidMode` must be set to `"task"` in the task definition
- `enableFaultInjection` must be set to `true` in the task definition
- An SSM agent sidecar container must be added to the task definition
- For Fargate, `useEcsFaultInjectionEndpoints` must be set to `true`
- ECS Exec must be disabled during experiments
- Additional IAM permissions are needed (task role, managed instance role, experiment role)

These are non-trivial changes to the production task definition and were out of scope for the chaos testing scripts.
