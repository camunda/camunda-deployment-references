# ECS single-region (Fargate) – Camunda 8 reference architecture

This folder describes the IaC of Camunda on AWS ECS Fargate in a single-region setup.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/next/self-managed/deployment/containers/cloud-providers/amazon/aws-ecs/

## Load testing

An optional overlay puts a Prometheus and a load generator next to the cluster,
so it can be watched under load instead of at rest. It is off by default:

```hcl
enable_load_tests = true
```

With the flag false nothing extra is planned, so the plan of this state is
unchanged for anyone who does not ask for it.

```bash
terraform apply -var enable_load_tests=true

# throughput, live
aws logs tail "$(terraform output -raw load_generator_log_group)" --follow

# Prometheus, from inside the VPC
terraform output -raw prometheus_endpoint
```

| Knob | Default | What it changes |
|---|---|---|
| `load_tests_start_rate` | `10` | Process instances started per second |
| `load_tests_retention_time` | `168h` | How far back Prometheus can be queried |
| `load_tests_prometheus_port` | `9090` | Port Prometheus listens on |

The generator authenticates as the `admin` user this state already creates, with
the password from Secrets Manager, because this reference deploys no Management
Identity and runs basic auth. Prometheus finds the cluster through Cloud Map
rather than a fixed address, so a redeployed cluster is picked up on its own.

Neither piece is exposed publicly. Prometheus answers on its private DNS name,
and the generator has no endpoint at all. Pair it with the
[FIS chaos experiments](../../common/procedure/chaos-fis/README.md) to see what
a broker restart or a lost Availability Zone does to the throughput number.

### Where this came from

The overlay is the part of
[`camunda/camunda-load-tests-ecs`](https://github.com/camunda/camunda-load-tests-ecs)
that made sense here, folded in under
[team-infrastructure-experience#464](https://github.com/camunda/team-infrastructure-experience/issues/464).
That repository built an ECS Camunda cluster plus load against it, and already
consumed this repository's `ecs/fargate/orchestration-cluster` and `aurora`
modules by commit pin, so most of the overlap was already one-directional.

What came across, and what did not:

| From | Landed as | Why |
|---|---|---|
| `aws/monitoring` | [`modules/ecs/fargate/monitoring`](../../modules/ecs/fargate/monitoring/README.md) | The persistent Prometheus and its Cloud Map discovery, which is the piece worth generalising |
| `aws/load_test` | [`modules/ecs/fargate/load-generator`](../../modules/ecs/fargate/load-generator/README.md) | Rewritten on the public community benchmark; the original pulled private `team-zeebe` images |
| `aws/chaos-tests` | [`common/procedure/chaos-fis`](../../common/procedure/chaos-fis/README.md) | Portable as-is once the account-specific defaults were parameterised |
| `aws/benchmark` | — | An ECS Camunda cluster with Aurora, which is what this reference architecture already is |
| `aws/stable` | — | A shared VPC, ECR and registry credentials read from Camunda's internal Vault, tied to one AWS account and to CIDRs coordinated with a private repository |

The two dropped states are the ones that only made sense inside Camunda's own
account. `aws/benchmark` would have been a second, worse copy of this state, and
`aws/stable` cannot be copied at all: its registry credentials come from
`vault.int.camunda.com` and its VPC CIDRs have to match what Camunda's network
repository expects. Nothing here needs either. The parts that carried the same
coupling were dropped with them: the GCP federation security group in the
monitoring stack, and the `dev`/`prod` state layout that existed because several
benchmarks shared one account.
