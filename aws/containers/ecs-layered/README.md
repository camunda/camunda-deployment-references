# Layered ECS reference architecture (proof of concept)

Camunda 8 on ECS Fargate, built from layers. Each layer is its own Terraform root: it takes
variables, produces outputs, and can be used on its own. A layer's outputs are the next
layer's variables, so bringing something you already have means passing its IDs and
skipping the code that would have created it.

| # | Layer | Root | Takes from | Produces |
|---|-------|------|------------|----------|
| 1 | Network | [`network`](terraform/network) | nothing, or your VPC IDs | `vpc_id`, `vpc_cidr`, `private_subnet_ids`, `public_subnet_ids`, `private_route_table_ids` |
| 2 | Compute | [`compute`](terraform/compute) | network | ECS cluster, task execution role, security groups, secrets key, registry credentials |
| 3 | Object storage | [`object-storage`](terraform/object-storage) | nothing | backup bucket, one node ID lease bucket per zone, access policies |
| 4 | Secondary storage | [`storage`](terraform/storage) | network, compute | `secondary_storage` connection settings, IAM connect policies |
| 5 | Exposure | [`exposure`](terraform/exposure) | network, compute | listeners, `public_base_url` |
| 6 | Identity | [`identity`](terraform/identity) | compute, exposure | `oidc` object or `null` (basic authentication) |
| 7 | Camunda | [`camunda`](terraform/camunda) | all of the above | Orchestration Cluster and Connectors |

[`procedure/compose.sh`](procedure/compose.sh) applies them in order and wires the outputs of
one layer into the variables of the next. It is the only place that knows the wiring; run a
layer by hand with `terraform apply -var-file=...` if you prefer.

```bash
export TF_STATE_BUCKET=my-state-bucket TF_STATE_REGION=eu-west-1
./procedure/compose.sh apply examples/greenfield      # new VPC
./procedure/compose.sh apply examples/byo-vpc         # existing VPC
```

## The management plane

Camunda Hub is one for the whole estate and connects to several Orchestration Clusters. It needs
Management Identity, which needs an OIDC provider, so these three form the management plane. It is
deployed once, with `PLAN=management`, with the same network, compute, storage, and exposure layers
as a cluster, and three more:

| Layer | Root | Takes from | Produces |
|-------|------|------------|----------|
| OIDC provider | [`oidc-provider`](terraform/oidc-provider) | network, compute, exposure, storage | `clusters` (one `external_oidc` object per Orchestration Cluster), `management` |
| Management Identity | [`management-identity`](terraform/management-identity) | the layers above, OIDC provider | `internal_url`, `hub_authorization_enabled` |
| Camunda Hub | [`hub`](terraform/hub) | the layers above, Management Identity, `cluster_registration` of each cluster | `public_url`, `clusters` |

```bash
PLAN=management ./procedure/compose.sh apply examples/management-plane
```

Each Orchestration Cluster then runs its identity layer with `authentication_mode = "oidc"` and the
`clusters` entry of the OIDC provider as `external_oidc` (`examples/management-plane/cluster`), and
its Camunda layer publishes `cluster_registration`, which goes into the `clusters` of the Camunda
Hub layer. The databases of the three components are declared in the storage layer (`databases`):
the storage layer creates the roles and the passwords, and the components read them from its output.

## Growing to a second region

[`EVOLVE-DUAL.md`](EVOLVE-DUAL.md) is the runbook: the delta only, with each step marked verified
or not verified. It adds two optional roots, [`interconnect`](terraform/interconnect) and
[`global-database`](terraform/global-database), runs the same layers again in the new region, and
adds a zone to the running cluster with [`procedure/add-zone.sh`](procedure/add-zone.sh). The
variables are in [`examples/dual`](examples/dual).

## Design points

- **Zone-aware brokers from day one.** The Orchestration Cluster runs with one zone and three
  brokers (`<zone>_0` to `<zone>_2`), replication factor 3. Growing to a second region later
  adds a zone through the management API; it does not rename or renumber the existing brokers.
  Increasing the number of brokers is fine; reducing it is not possible without losing data.
- **An internal load balancer for the brokers from day one.** The examples set `enable_raft_nlb` and
  `enable_raft_listener`. Nothing uses it in a single region, but it is what lets the second region's
  brokers join later without Terraform replacing the Orchestration Cluster ECS service.
- **One node ID lease bucket per zone.** On ECS a broker leases its node index from S3, with
  conditional writes scoped to the bucket. A lease bucket is never shared between zones or
  clusters.
- **Secondary storage starts as a standalone Aurora cluster.** It converts in place to an
  Aurora Global Database, but not from `db.t3`/`db.t4g`: start from an r-class instance if you
  plan to grow.
- **No remote state between layers.** The roots only read variables.

## Not part of this proof of concept

Load tests, and generated golden plans. Adding an Orchestration Cluster to a running OIDC provider:
the realm is imported when the provider starts for the first time, so a cluster that you add later is
registered in the provider's administration console with the values of the `clusters` output, the same
way as for an OIDC provider that you run yourself.

## Validation

Each layer has `terraform test` files that run with mocked providers: `terraform init
-backend=false && terraform test` in the root.
