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

## Design points

- **Zone-aware brokers from day one.** The Orchestration Cluster runs with one zone and three
  brokers (`<zone>_0` to `<zone>_2`), replication factor 3. Growing to a second region later
  adds a zone through the management API; it does not rename or renumber the existing brokers.
  Increasing the number of brokers is fine; reducing it is not possible without losing data.
- **One node ID lease bucket per zone.** On ECS a broker leases its node index from S3, with
  conditional writes scoped to the bucket. A lease bucket is never shared between zones or
  clusters.
- **Secondary storage starts as a standalone Aurora cluster.** It converts in place to an
  Aurora Global Database, but not from `db.t3`/`db.t4g`: start from an r-class instance if you
  plan to grow.
- **No remote state between layers.** The roots only read variables.

## Not part of this proof of concept

Parked, with the decisions already taken:

- **OIDC provider deployed on ECS.** Called "OIDC provider" in code and docs, never by the
  product name; the first implementation will be the one the single-region reference ships
  today. It is a second producer of the identity layer's `oidc` object, so the Camunda layer
  does not change.
- **Management Identity.** Follows the OIDC provider: it needs an OIDC provider and its own
  database in the storage layer.
- **Camunda Hub.** One Hub for the whole estate, connectable to several Orchestration
  Clusters, so it is its own layer (`hub`), not part of the `camunda` layer. It takes its own
  database and the identity layer's `oidc` object, and the Orchestration Clusters it manages
  are a list of inputs (name, URLs, client) rather than something one cluster owns.

Also out of this proof of concept: load tests, the second region (see the evolution
runbook), and generated golden plans.

## Validation

Each layer has `terraform test` files that run with mocked providers: `terraform init
-backend=false && terraform test` in the root.
