# AWS EKS multi-region with RDBMS secondary storage

> [!WARNING]
> This reference architecture is experimental and intended for learning,
> evaluation, and design review. It is not production-ready.

This reference deploys one Camunda 8 Orchestration Cluster across three or more
AWS regions. Zeebe keeps quorum after one region is lost, while an RDBMS handles
secondary-storage replication and writer failover.

Start with the published [multi-region resilience overview](https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/resilience-tiers/).
The detailed architecture, deployment procedure, and day-2 operations are being
reviewed in [camunda-docs pull request #9739](https://github.com/camunda/camunda-docs/pull/9739).


## Deploy

```bash
./procedure/get-your-copy.sh

cd terraform/clusters
terraform init -backend=false
terraform apply -var cluster_name=camunda

cd ../../procedure
. ./export-terraform-outputs.sh
. ./export_environment_prerequisites.sh
./register-kubecontexts.sh
./storageclass-configure.sh
./storageclass-verify.sh
source ./submariner/install-subctl.sh
./submariner/deploy-broker.sh
./submariner/join-clusters.sh
./submariner/verify-submariner.sh
./setup-namespaces.sh
./verify-cross-region-connectivity.sh
./create-rdbms-secret.sh
. ./generate-zeebe-helm-values.sh
./assemble-envsubst-values.sh
./install-chart.sh
./submariner/export-services.sh
./check-cluster-topology.sh
```

For repeatable settings, place Terraform variables in a local file and pass it
to every plan and apply:

```hcl title="terraform-cluster.tfvars"
cluster_name            = "camunda"
kubernetes_version      = "1.36"
active_region_count     = 3
np_desired_node_count   = 4
single_nat_gateway      = false
database_instance_class = "db.r6g.large"
default_tags = {
  environment = "evaluation"
}
```

```bash
terraform apply -var-file=terraform-cluster.tfvars
```

The connectivity probe uses `busybox:1.37` by default. Set `PROBE_IMAGE` before
running `verify-cross-region-connectivity.sh` to use an approved mirror or a
different image.

The Aurora clusters use private subnets. Their security groups allow PostgreSQL
on TCP port 5432 only from the active cluster VPC CIDRs. The database is not
publicly accessible.

The Helm values file contains only overrides for this architecture. Compare it
with the [Camunda Helm chart defaults](https://github.com/camunda/camunda-platform-helm/blob/main/charts/camunda-platform-8.10/values.yaml)
when changing chart configuration.

## Activate a declared region

Raise `active_region_count`, apply Terraform, refresh the exported topology, and
run the activation procedure:

```bash
terraform apply -var-file=terraform-cluster.tfvars
cd ../../procedure
. ./export-terraform-outputs.sh
. ./export_environment_prerequisites.sh
./register-kubecontexts.sh
./activate-region.sh <slot>
```

`activate-region.sh` fills a zone declared at bootstrap. It does not add a new
zone to a running cluster.

## Day-2 commands

| Task | Command |
|---|---|
| Verify topology | `./procedure/check-cluster-topology.sh` |
| Measure database latency | `./procedure/measure-rdbms-latency.sh` |
| Handle region loss | `./procedure/failover.sh <slot>` |
| Bring a region back | `./procedure/failback.sh <slot> [--switch-writer]` |
| Diagnose cross-region networking | `./procedure/submariner/diagnose-submariner.sh` |
