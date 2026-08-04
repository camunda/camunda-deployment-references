# Developer's Guide

Local development reference for the AWS EKS multi-region RDBMS architecture.
Read [README.md](./README.md) first: the topology invariants (region slots,
replication factor, node ID stride) are not obvious and getting them wrong
produces a cluster that silently never forms a quorum.

## Prerequisites

```bash
just install-tooling   # terraform, kubectl, helm, yq, jq, go
pre-commit install
```

Plus:

- `subctl` — installed by `procedure/submariner/install-subctl.sh`
- an AWS profile with access to **all** the regions in play

> [!WARNING]
> `eu-central-2` (Zurich) and `eu-south-1` (Milan) are AWS **opt-in** regions.
> They must be enabled on the account before anything can be created there:
> `aws account enable-region --region-name eu-central-2`. Their cleanup schedule
> also has to be declared in
> [infraex-common-config](https://github.com/camunda/infraex-common-config).

> [!WARNING]
> `eu-west-2` and `eu-west-3` are nuked nightly. Use a `cluster_name` of your
> own, never the CI default, and expect anything left running overnight to be
> gone.

## Cost awareness

This architecture is significantly more expensive than the dual-region one:

- 3 EKS control planes and node groups instead of 2
- 3 Transit Gateways plus 3 inter-region peering attachments, billed per
  attachment-hour **and** per GB of inter-region data
- 1 Aurora Global Database with a member per database region

Destroy it as soon as you are done. `single_nat_gateway = true` and a smaller
`np_desired_node_count` cut a meaningful share of the bill for local iteration.

## Bringing it up

```bash
cd terraform/clusters
terraform init

# Local iteration: 2 of 3 slots, smallest viable footprint.
terraform apply \
  -var cluster_name="$USER-mr" \
  -var active_region_count=2 \
  -var single_nat_gateway=true \
  -var np_desired_node_count=2
```

`active_region_count=2` with 3 slots is a valid, supported state: every
partition holds 2 of its 3 replicas. It halves the cost while still exercising
the cross-region code paths, and it is the starting point of the
`activate-region.sh` flow.

Then:

```bash
# kubectl contexts, aliased to the names in CLUSTER_CONTEXTS
for pair in "eu-west-2:$USER-mr-london:cluster-london" \
            "eu-west-3:$USER-mr-paris:cluster-paris"; do
  IFS=: read -r region name alias <<<"$pair"
  aws eks --region "$region" update-kubeconfig --name "$name" --alias "$alias"
done

cd ../../procedure
. ./export-terraform-outputs.sh
export CAMUNDA_ACTIVE_REGIONS=2
export CLUSTER_CONTEXTS="cluster-london cluster-paris"
. ./export_environment_prerequisites.sh

./configure-vpc-cni-custom-networking.sh
```

`export-terraform-outputs.sh` derives most of the environment from the state, so
only the kubectl context aliases really need to be provided by hand.

`configure-vpc-cni-custom-networking.sh` terminates every node, so allow around
ten minutes per region for the node group to bring the capacity back. Skipping
it is the fastest way to reproduce the failure this architecture is designed to
avoid: the pods keep routable VPC addresses, the Transit Gateway and Submariner
both own them, and the brokers never form a quorum.

## Debugging

### Cross-region pod traffic is dropped

Before blaming Camunda, prove the substrate:

```bash
./verify-cross-region-connectivity.sh
```

Two minutes instead of the thirty a full deployment takes. If it fails, check
the ownership of the pod range:

```bash
# Pods must be in 100.64.0.0/10, NOT in the VPC CIDR
kubectl --context cluster-london -n camunda get pods -o wide

# Submariner must report the pod and service CIDRs, never the VPC CIDR
subctl show all --contexts cluster-london
```

A cluster reporting the VPC CIDR was joined before
`configure-vpc-cni-custom-networking.sh` ran, or with `--clustercidr` pointed at
`REGION_VPC_CIDRS`. Re-run the procedure and rejoin the cluster.

If instead the tunnels look perfect and the brokers still log
`Poll request to N failed ... connection timed out`, the source address is
being rewritten. Check the exclusion list:

```bash
kubectl --context cluster-london -n kube-system get daemonset aws-node \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS")].value}'
```

It must list every **remote** pod and service range. Empty means the CNI is
source-NATing cross-region pod traffic to the node address, which the remote
security group rejects because those rules are written for pod ranges.

### Zeebe never reaches the expected broker count

Almost always cross-region DNS. In order:

```bash
./submariner/verify-submariner.sh          # are the tunnels up?
./submariner/diagnose-submariner.sh        # full dump incl. cross-cluster nslookup
kubectl --context cluster-london -n camunda logs camunda-zeebe-0 -c wait-clusterset-dns
```

The `wait-clusterset-dns` init container logs exactly which name it is waiting
for. If it times out and the broker starts anyway (fail-open), the broker will
then hang on `NXDOMAIN` while dialing a peer — see
[camunda/camunda#55038](https://github.com/camunda/camunda/issues/55038).

### A broker is `Running` but never `Ready`

Same root cause. Delete the pod; it re-resolves on restart.

### Brokers are up but partitions are unhealthy

Check the node ID distribution. Every region slot must own its residue class:

```bash
./check-cluster-topology.sh
```

If a slot owns the wrong node IDs, `global.multiregion.regions` does not match
the Terraform slot count. That is a bootstrap-time mistake and cannot be fixed
in place.

### RDBMS connection failures

```bash
kubectl --context cluster-london -n camunda logs camunda-zeebe-0 | grep -i -E 'jdbc|hikari|liquibase'
```

Common causes:

- the Aurora security group does not include the region's VPC, service or pod
  CIDR — check `database_allowed_cidr_blocks` in
  `terraform/clusters/database.tf`. Pods reach a **local** Aurora member with
  their own address, and a **remote** one with the node address, because the
  VPC CNI only source-NATs traffic leaving the VPC;
- the writer moved and `globalClusterInstanceHostPatterns` does not list the new
  region;
- Liquibase is blocked on `DATABASECHANGELOGLOCK` after a crashed startup.

## Exercising the interesting paths

```bash
# Grow the cluster from 2 to 3 regions without touching the running brokers
cd terraform/clusters && terraform apply -var active_region_count=3 && cd -
aws eks --region eu-central-2 update-kubeconfig --name "$USER-mr-zurich" --alias cluster-zurich
export CLUSTER_CONTEXTS="cluster-london cluster-paris cluster-zurich"
export CAMUNDA_ACTIVE_REGIONS=3
./activate-region.sh 2

# Lose a region and observe that nothing stops
./failover.sh 1
./check-cluster-topology.sh

# Bring it back
./failback.sh 1
```

## Tearing down

```bash
helm --kube-context cluster-london -n camunda uninstall camunda || true
# ... one per region

cd terraform/clusters
terraform destroy -var cluster_name="$USER-mr"
```

Destroy order matters: Kubernetes-managed load balancers and ENIs keep the VPC
alive. If `terraform destroy` stalls on a VPC or subnet, look for leftover
LoadBalancer services and Submariner gateway resources first.

## Golden files

```bash
just regenerate-golden-file eks-multi-region-rdbms eu-west-2
```

Golden plans are regenerated from `terraform/clusters/test/golden/golden.tfvars`.
Never edit them by hand, and check the redaction before committing.
