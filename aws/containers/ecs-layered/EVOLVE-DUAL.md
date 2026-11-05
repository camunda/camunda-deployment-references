# Growing from one region to two

You have the single-region deployment of this directory and want a second region without
rebuilding the first. Only the delta is described here.

**Status of every step.** `verified` means it was run or read in the product source or
documentation. `not verified` means it follows from the design and has not been run on AWS.
Nothing in this runbook was applied from the workbench that wrote it, which has no cloud
credentials; the Aurora steps are the exception: they come from an experiment run against
real regions (see step 1, 6 and 7).

## What the starting point must already be

| Requirement | Why | Where |
|-------------|-----|-------|
| Zone-aware brokers (the default of the `camunda` layer: one zone, three brokers) | A zone is added to a running cluster. Numbered brokers would first need an irreversible migration, which this directory does not cover. | `camunda` layer |
| A lease bucket per zone | The lease is scoped to the bucket. Never share one. | `object-storage` layer |
| An r-class or serverless Aurora instance | Aurora Global Databases do not support `db.t3` or `db.t4g`. | step 1 |
| Non-overlapping VPC CIDRs | Peering needs it. | step 2 |
| `enable_raft_nlb = true` and `enable_raft_listener = true` from the start (the single-region examples set both) | Region B's brokers reach region A through the internal load balancer. Adding it later makes Terraform register a target group on an existing ECS service, which may replace the service (see step 5). The variable defaults to `false`: set it yourself if you do not start from the examples. | `exposure` and `camunda` layers |

You can increase the number of brokers later. You cannot reduce it without losing data.

## What changes in the existing region, and what is redeployed

| Layer in region A | Change | Effect |
|-------------------|--------|--------|
| `storage` | `db_instance_class` to an r-class, then `global_cluster_identifier`, `additional_cidr_blocks` | Resize: in place, search is unavailable for a few minutes (measured ~4 min). The rest is an update. |
| `compute` | `additional_cidr_blocks` | Security group rules added. No restart. |
| `exposure` | `enable_raft_nlb = true` | A load balancer is added. No restart. |
| `camunda` | Raft listener, then the global endpoint, then the full zone list | Three rolling restarts of the brokers, possibly one service replacement (step 5). Each ECS environment change is a new task definition. |
| `network`, `object-storage`, `identity` | none | |

Everything else is new and lives in region B or spans both: `interconnect`,
`global-database`, and the layers of region B.

## Steps

### 1. Make the database global-capable (region A) — verified

Set `db_instance_class` of the storage layer to an r-class (`db.r6g.large`) and apply.

Measured: in place, 7 m 29 s, Camunda search unavailable for about 4 minutes while the single
instance restarts. Zeebe kept accepting writes and recovered on its own. Add a reader
instance first (`db_num_instances = 2`) if you cannot accept that window; whether a reader
turns it into a failover instead is not verified.

### 2. Network of region B

Run the `network` layer in region B: `examples/dual/region-b/network.tfvars`, or
`byo_vpc = true` with your IDs. With `compose.sh`:

```bash
AWS_REGION=eu-north-1 STATE_KEY_PREFIX=region-b/ WORK_DIR=./debug/region-b \
  SKIP_LAYERS="compute object-storage storage exposure identity camunda" \
  ./procedure/compose.sh apply examples/dual/region-b
```

### 3. Interconnect — not verified

Apply the `interconnect` root (`examples/dual/interconnect.tfvars`). It creates a VPC
peering connection, routes in the private route tables of both VPCs, and Route 53 Resolver
rules that forward each region's service discovery domain to the other. It does not change
the VPCs. Use a transit gateway instead for three or more regions; the dual-region reference
has an implementation, this directory does not.

### 4. Open the ports (region A) — not verified

Pass the output `additional_cidr_blocks_a` as `additional_cidr_blocks` to the `compute` and
`storage` layers of region A (`examples/dual/region-a`) and apply. It only adds rules.

### 5. Prepare region A for the other region's brokers — partly verified

If you started from the single-region examples, both settings are already on: skip to step 6.
Otherwise apply `exposure` with `enable_raft_nlb = true`, then `camunda` with
`enable_raft_listener = true` (`examples/dual/region-a`).

Before you apply the `camunda` layer: **read the plan**. If it shows the ECS service
`orchestration-cluster` being replaced rather than updated, the cluster is down while it is
recreated. That is the reason to enable the Raft load balancer from the start. Not verified:
whether the provider replaces or updates the service when a load balancer is added.

### 6. The global database — verified (plain connection)

1. Apply the `global-database` root (`examples/dual/global-database.tfvars`, values from the
   storage layer's outputs). It creates the global cluster **from** the existing cluster:
   measured, one resource to add, the cluster untouched, 12 seconds, no errors in Camunda.
2. The secondary cluster in region B: 14 resources, about 8.5 minutes, no errors in Camunda.
3. Set `global_cluster_identifier` on the `storage` layer to the root's output and apply.
   Without it a plan shows the attribute going back to `null`, which would detach the cluster
   from the global database: measured, in place and silent.

### 7. Point region A at the global endpoint — partly verified

Apply the `camunda` layer of region A with the global database's outputs instead of the
storage layer's: `secondary_storage` (global writer endpoint) and
`rds_db_connect_policy_arns["camunda"]` (a policy that names both clusters; after a
failover the writer is the other one). Camunda restarts.

Measured: with only the host changed to the global endpoint, ready in 10 seconds and no
instance lost, **using the plain PostgreSQL driver**. The URL built here uses the AWS JDBC
wrapper with `initialConnection,iam,failover` and `globalClusterInstanceHostPatterns`, which
is what an IAM-authenticated global endpoint needs (as in the dual-region reference).
Not verified: that combination here, and switchover or failover behind the endpoint (DNS TTL,
pooled connections).

### 8. Region B — not verified

Run the remaining layers in region B. The storage layer is not run: the database is the
global one (`STORAGE_OUTPUTS_FILE` points at the `global-database` outputs).

```bash
terraform -chdir=terraform/global-database output -json > debug/global-database.outputs.json
AWS_REGION=eu-north-1 STATE_KEY_PREFIX=region-b/ WORK_DIR=./debug/region-b \
  STORAGE_OUTPUTS_FILE=debug/global-database.outputs.json SKIP_LAYERS="network storage" \
  ./procedure/compose.sh apply examples/dual/region-b
```

Points that are easy to get wrong:

- `object-storage` with `zones = ["zone-b"]`: its own lease bucket.
- `camunda`: `zone = "zone-b"` and the **full** zone list. The broker looks its zone up in
  the list at start-up and fails if it is not there (`NodeIdProviderConfigurationUtils`).
  The list in region A has not changed yet; that is expected: the zone list is only the
  seed of the first start, afterwards the cluster's own configuration prevails.
- `initial_contact_points`: its own name and region A's `nlb_raft_dns_name`.
- In basic authentication mode, pass region A's `admin_user_password` and
  `connectors_user_password`: the users exist in the cluster, not in each region.
- `rdbms_async_replication_monitoring = true`: the exporter then waits for the replica region.

The brokers of region B start, join the cluster and host no partition yet.

### 9. Add the zone — API verified, ECS path not verified

```bash
./procedure/add-zone.sh --region eu-west-1 --ecs-cluster camunda-demo-cluster \
  --prefix camunda-demo-oc --zone zone-b --brokers 3 --replicas 3 --priority 500 --dry-run
# then again without --dry-run
```

It tunnels to a broker of region A over ECS Exec and calls
`POST /actuator/cluster/zones/zone-b`, then waits for the change to complete. Replication
factor becomes the sum of the zones' replicas (6 here: each region holds a full copy of
every partition). The partition count does not change.

Layout to choose before you run it: with `3 + 3` replicas, losing a region leaves 3 of 6
replicas, so processing stops until you fail over by removing the zone
(`DELETE /actuator/cluster/zones/<zone>?force=true`; the `failover.sh` of the dual-region
reference does that, but it assumes its own names and is not verified here). It is the
dual-region trade-off, not a bug: for a cluster that survives losing a region, add a third
zone (below).

### 10. Converge region A's configuration — not verified

Apply `camunda` in region A with `examples/dual/region-a/camunda-converged.tfvars`: the full
zone list, `cross_region_membership`, `rdbms_async_replication_monitoring`. Brokers restart
one by one. Not verified: whether this is required. The configuration of a running cluster
comes from its own state, so a restart with the old list may work; but a task that starts
with a list that differs from what the other zone runs is a surprise you can avoid.

### 11. Check

- `GET /actuator/cluster`: both zones, brokers `zone-a_0..2` and `zone-b_0..2` active.
- `GET /v2/topology`: every partition has replicas in both zones.
- Start a process instance in each region's load balancer; both are served by the cluster.
- The exporter lag of the async replication monitoring stays low.

## Backing out

Remove the zone first (`DELETE /actuator/cluster/zones/zone-b`, graceful when the zone is
healthy), wait for completion, then destroy region B's layers in reverse order, then the
interconnect. The Aurora global database is not reversible in place: detaching the secondary
is possible, turning the global cluster back into a standalone one is not covered here.

## Three regions — not built

The same procedure once more: a VPC, a lease bucket, the layers and a `zone-c`. Use a transit
gateway rather than three peerings, add a secondary to the global database (up to five), and
choose the layout deliberately: the documentation's example is `2-2-1` replicas over three
zones, replication factor 5, which survives the loss of either database region. Adding a
zone does not renumber the brokers that run.
