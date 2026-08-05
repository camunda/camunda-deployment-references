# AWS EKS multi-region with RDBMS secondary storage

> [!WARNING]
> This reference architecture is **experimental**. Camunda documents and
> supports **two** regions; the topology described here goes beyond that and is
> intended for learning, evaluation and design review — not for production.
> Talk to your Customer Success Manager before planning any multi-region
> deployment, and expect this document to change.

A Camunda 8.10 Orchestration Cluster stretched across **N AWS regions**
(3 by default), backed by a relational secondary storage whose replication is
entirely the database's responsibility.

The design goal is to remove the two structural weaknesses of the dual-region
architecture:

| | Dual region (existing) | Multi region (this) |
|---|---|---|
| Region loss | Zeebe loses quorum and **stops processing** until brokers are force-removed | Quorum is preserved, Zeebe **keeps processing** |
| Failback | 8 steps, including an Elasticsearch snapshot and restore | Redeploy the region; nothing to restore |
| Secondary storage | One Elasticsearch cluster per region, two Camunda exporters, manual re-initialisation | One database, one exporter, replication handled by the database |
| Cross-region DNS | CoreDNS stub forwarding, `O(N²)` stanzas, pod IPs only | Submariner Lighthouse, `*.svc.clusterset.local`, ClusterIP and headless |
| Cross-region L3 | VPC peering mesh, `O(N²)` peerings and route entries | Transit Gateway, one attachment per VPC |
| Adding a region | Not possible | Possible, without renumbering brokers |

---

## Contents

- [Topology](#topology)
- [Why the replication factor equals the number of regions](#why-the-replication-factor-equals-the-number-of-regions)
- [Region slots vs active regions](#region-slots-vs-active-regions)
- [Replication-agnostic secondary storage](#replication-agnostic-secondary-storage)
- [Cross-region networking](#cross-region-networking)
- [Deploy](#deploy)
- [Day-2 operations](#day-2-operations)
- [Known limitations](#known-limitations)
- [Regions used](#regions-used)

---

## Topology

Default shape, 3 regions:

```
        eu-west-2 (London)        eu-west-3 (Paris)        eu-central-2 (Zurich)
        region slot 0             region slot 1            region slot 2
        ┌───────────────┐         ┌───────────────┐        ┌───────────────┐
        │ EKS           │         │ EKS           │        │ EKS           │
        │  zeebe-0 (id0)│         │  zeebe-0 (id1)│        │  zeebe-0 (id2)│
        │  zeebe-1 (id3)│         │  zeebe-1 (id4)│        │  zeebe-1 (id5)│
        │  connectors   │         │  connectors   │        │  connectors   │
        └───────┬───────┘         └───────┬───────┘        └───────┬───────┘
                │      Transit Gateway full mesh + Submariner      │
                └─────────────────────────┼───────────────────────-┘
                                          │
                            ┌─────────────┴─────────────┐
                            │  Aurora Global Database   │
                            │  writer: eu-west-2        │
                            │  reader: eu-west-3        │
                            └───────────────────────────┘
```

| Setting | Default | Meaning |
|---|---|---|
| `regions` (Terraform) | 3 slots | London, Paris, Zurich |
| `global.multiregion.regions` | 3 | Node ID stride, **immutable** |
| `orchestration.clusterSize` | 6 | `brokersPerRegion * regionSlots` |
| `orchestration.partitionCount` | 6 | One partition per broker |
| `orchestration.replicationFactor` | 3 | One replica per region |
| `database_region_slots` | `[0, 1]` | Aurora members, writer first |

Broker node IDs follow the Helm chart formula
`nodeId = statefulSetOrdinal * regions + regionId`, so slot *k* owns the node
IDs congruent to *k* modulo the slot count.

---

## Why the replication factor equals the number of regions

Zeebe distributes partitions round robin over **consecutive node IDs**: partition
*p* is replicated on nodes `p-1, p, p+1, …` modulo `clusterSize`
([partition distribution][partitions]). Combined with the chart's node ID
stride, `replicationFactor == regionSlots` places **exactly one replica of every
partition in every region**:

```
clusterSize 6, partitionCount 6, replicationFactor 3, 3 region slots
node IDs:  slot 0 → {0, 3}   slot 1 → {1, 4}   slot 2 → {2, 5}

partition 1 → nodes 0,1,2  → one replica per region
partition 2 → nodes 1,2,3  → one replica per region
…
partition 6 → nodes 5,0,1  → one replica per region
```

A partition keeps its Raft majority as long as `N-1 > N/2`, which holds for
every `N >= 3`. So:

| Region slots | Replication factor | Region losses tolerated |
|---|---|---|
| 2 | 4 (dual-region convention) | **0** — quorum is lost |
| 3 | 3 | 1 |
| 4 | 4 | 1 |
| 5 | 5 | 2 |

This is why the dual-region architecture needs a failover procedure at all: with
two regions there is no assignment of an even replica count that survives losing
half of it. Three regions is the smallest topology where a region can disappear
and the workflow engine simply carries on.

Using a multiple of the slot count (`replicationFactor = 2 * regionSlots`) puts
two replicas per region and increases intra-region durability at the cost of
write amplification. It does not change the region fault tolerance.

[partitions]: https://docs.camunda.io/docs/components/zeebe/technical-concepts/partitions/#partition-distribution

---

## Region slots vs active regions

The Camunda Helm chart derives every broker's identity from the region count:

```
nodeId = statefulSetOrdinal * global.multiregion.regions + regionId
```

Changing `regions` renumbers **every** broker in the cluster, which a running
Raft cluster cannot survive. The region count is therefore treated as a **slot
count, fixed at bootstrap**, and regions are brought online independently:

- `var.regions` — the slot definitions. Immutable for the lifetime of the
  Camunda cluster. Plan for the largest topology you expect.
- `var.active_region_count` — how many slots are actually deployed. Can be
  raised at any time.

Bootstrapping with one slot empty is supported and is the intended growth path:
every partition then has `N-1` of its `N` replicas, which is still a majority, so
the cluster forms and processes normally. Leaving **two or more** slots empty is
rejected by `terraform/clusters/checks.tf`, because every partition would lose
its majority.

```
3 slots, 2 active                    3 slots, 3 active
partition 1 → nodes 0,1,[2]          partition 1 → nodes 0,1,2
              2/3 replicas ✔                       3/3 replicas ✔
              tolerates 0 losses                   tolerates 1 loss
```

Activating the last slot is a single command and does not restart the running
regions:

```bash
export CAMUNDA_ACTIVE_REGIONS=3
./procedure/activate-region.sh 2
```

**What this does not do:** grow a cluster from 3 slots to 4. That requires
renumbering and is a rebuild. If you may need a fourth region later, provision
four slots up front and leave the last one inactive.

---

## Replication-agnostic secondary storage

Camunda 8.10 exposes **one JDBC connection per Orchestration Cluster** and the
RDBMS exporter has no multi-region mode
([documentation][rdbms-multiregion]): *"Multi-region support for the RDBMS
Exporter is not planned at this time. For multi-region setups, multi-region
replication must be handled within the RDBMS itself."*

This reference architecture takes that constraint and turns it into the design:

- Every broker in every region writes to the **same JDBC URL**.
- There are **no per-region exporters** to enable, disable or re-initialise.
- Region loss does not desynchronise anything at the Camunda layer, so failback
  has no snapshot and restore step.
- Swapping the database swaps one variable.

The reference implementation is **Aurora Global Database** reached through the
[AWS Advanced JDBC Wrapper][jdbc-wrapper]:

```
jdbc:aws-wrapper:postgresql://<writer-endpoint>:5432/camunda
  ?wrapperPlugins=failover
  &globalClusterInstanceHostPatterns=?.<region0-suffix>,?.<region1-suffix>
```

The `failover` plugin enumerates the instances of every listed region, so a
global failover is followed by the driver without restarting or reconfiguring
Camunda.

To use something else, set `deploy_database = false` and provide your own
`CAMUNDA_RDBMS_URL`. Anything exposing a single endpoint that follows the writer
works the same way: Patroni with a floating endpoint, RDS Proxy, PgCat, an
AlloyDB or CockroachDB cluster, or a plain DNS CNAME you repoint during
failover.

> [!IMPORTANT]
> `CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_ENABLED=true` is
> **required**, not a tuning knob. Without it the RDBMS exporter does not
> enable async replication and an Aurora failover can lose exported data —
> which this architecture treats as a routine operation, not an incident.

> [!IMPORTANT]
> The Zeebe data plane is active-active across all regions. The **database tier
> is active-standby**: a single writer serves every region. Brokers that are not
> co-located with the writer pay the inter-region round trip on every export
> flush. Keep regions within the [100 ms RTT budget][rtt] and size
> `orchestration.data.secondaryStorage.rdbms.queueSize` accordingly.
> `./procedure/measure-rdbms-latency.sh` reports the actual cost per region.

[rdbms-multiregion]: https://docs.camunda.io/docs/next/self-managed/concepts/databases/relational-db/database-configuration/#multi-region-support
[jdbc-wrapper]: https://github.com/aws/aws-advanced-jdbc-wrapper
[rtt]: https://docs.camunda.io/docs/next/self-managed/concepts/multi-region/dual-region/#installation-environment

---

## Cross-region networking

Two layers, both chosen because they scale with the number of regions.

### L3: Transit Gateway

One Transit Gateway per region, one VPC attachment each, and a full mesh of
inter-region peerings. Transit Gateway peering is **not transitive**, so the
mesh has `N*(N-1)/2` edges — 3 for three regions, 6 for four.

Compared with the VPC peering mesh used by the dual-region architecture, the
number of *route table entries and attachments per VPC* stays constant as
regions are added, and the same hub can later carry Direct Connect or
site-to-site VPN attachments.

CIDRs must not overlap across regions. The defaults are:

| Slot | Region | VPC / pod CIDR | Service CIDR |
|---|---|---|---|
| 0 | eu-west-2 | `10.192.0.0/16` | `10.190.0.0/16` |
| 1 | eu-west-3 | `10.202.0.0/16` | `10.200.0.0/16` |
| 2 | eu-central-2 | `10.212.0.0/16` | `10.210.0.0/16` |
| 3 | eu-south-1 | `10.222.0.0/16` | `10.220.0.0/16` |

There is no separate pod range, and that is the point. With the AWS VPC CNI a
pod address is an ordinary VPC address, so routing the VPC range over the
Transit Gateway makes **cross-region pod-to-pod traffic work natively, with no
overlay**. The service range is routed too, because Lighthouse resolves a remote
ClusterIP service out of the exporting cluster's service range.

### Why there is no encrypted overlay

Submariner is deployed with its **service-discovery component only**
(`subctl deploy-broker --components service-discovery`). It provides multi-cluster
DNS and nothing else: no gateway nodes, no IPsec, no VXLAN, no route agent.
`subctl show connections` is empty by design.

This is a deliberate reversal of the more obvious design, and it is worth
recording why, because the obvious one was built first and does not work.

Running Submariner's connectivity component alongside the VPC CNI puts **two
owners on the same prefixes**. Submariner installs node routes for every remote
cluster CIDR so it can pull that traffic into its tunnel; with the VPC CNI those
CIDRs are the VPC ranges, which the Transit Gateway also routes — including the
node addresses the tunnels themselves are built on. Symptom: tunnels report
`connected`, clusterset DNS resolves to the right pod address, and every Raft
message is dropped.

Separating the ranges was tried: a VPC secondary CIDR out of `100.64.0.0/10`
carried the pods through VPC CNI custom networking, deliberately left out of the
Transit Gateway route tables. That got further — Submariner correctly reported
`Cluster CIDRs: [100.64.0.0/16]` and bound its gateway to the custom-networking
interface — and still failed, for a second reason: custom networking installs
per-pod source routing (`ip rule from <podIP> lookup <eni-table>`), so
pod-originated traffic never consults the main routing table where Submariner
installs its routes. The tunnel was healthy and unused.

Removing one of the two owners removes the whole class of problem. The Transit
Gateway is the one that cannot be removed, so Submariner keeps only the part
that does not touch the data path.

What this costs: cross-region traffic crosses the AWS backbone **unencrypted**.
It stays on private addresses and never touches the internet, but it is not
encrypted in transit, where the overlay would have provided IPsec. That is the
trade this architecture makes, and it is listed under
[Known limitations](#known-limitations).

### L4/L7: Submariner

[Submariner][submariner] provides cross-cluster service discovery. It is
deployed **upstream** (`subctl deploy-broker` and `subctl join`), not through the
Red Hat ACM add-on used by the OpenShift dual-region reference, because ACM is
OpenShift-only.

- **`--components service-discovery`**: Lighthouse only, for the reasons above.
- **Globalnet disabled**: CIDRs are already non-overlapping, which Transit
  Gateway requires anyway.
- `--clustercidr` is the VPC range, because that is where pods are addressed
  from, and `--servicecidr` is what a remote ClusterIP resolves to. Both are
  registered so the other clusters know which prefixes belong to which cluster;
  reaching them is the Transit Gateway's job.

Lighthouse publishes exported services as
`<clusterID>.<service>.<namespace>.svc.clusterset.local`. This is what lets the
architecture use **one namespace name in every cluster** instead of the
`N` namespaces replicated `N` times that CoreDNS stub forwarding would need.

Firewall rules are in `terraform/clusters/security.tf` and are written out
explicitly rather than "allow all between VPCs", because the port list is the
part a reader actually needs. There are no tunnel ports: there is no tunnel.

| Port | Protocol | Purpose |
|---|---|---|
| 26500-26502 | TCP | Zeebe gateway gRPC, command API, and the internal API carrying Raft |
| 8080 | TCP | Orchestration Cluster v2 REST API |
| 9600 | TCP | Orchestration management API |
| 53 | TCP/UDP | CoreDNS and Lighthouse |
| — | ICMP | Cross-region connectivity diagnostics |

Each rule is instantiated once per remote VPC range and once per remote service
range, so the count grows linearly with the region count: 24 inbound rules at
three regions, 36 at four, against an AWS limit of 60 per security group.
`checks.tf` asserts that budget at plan time rather than letting the apply fail
after the clusters exist.


[submariner]: https://submariner.io/

---

## Deploy

```bash
# 0. Get a copy
./procedure/get-your-copy.sh

# 1. Infrastructure: EKS clusters, Transit Gateway mesh, Aurora Global Database
cd terraform/clusters
terraform init -backend=false
terraform apply -var cluster_name=camunda

# 2. Environment
cd ../../procedure
. ./export-terraform-outputs.sh
. ./export_environment_prerequisites.sh

# 3. kubectl contexts, one per active region
#    aws eks --region <region> update-kubeconfig --name <cluster> --alias <context>

# 4. Storage
./storageclass-configure.sh
./storageclass-verify.sh

# 5. Submariner service discovery
source ./submariner/install-subctl.sh
./submariner/deploy-broker.sh
./submariner/join-clusters.sh
./submariner/verify-submariner.sh

# 6. Substrate check: two minutes, before spending twenty-five on Camunda.
#    Submariner does not carry this traffic, so nothing else covers the
#    Transit Gateway routes and the firewall rules.
./setup-namespaces.sh
./verify-cross-region-connectivity.sh

# 7. Camunda
./create-rdbms-secret.sh
. ./generate-zeebe-helm-values.sh
./assemble-envsubst-values.sh
./install-chart.sh
./submariner/export-services.sh

# 8. Verify
./check-cluster-topology.sh
```

Expect roughly 25 minutes for the EKS clusters, 15 for the Aurora Global
Database (both in parallel), 3 for Submariner and 10 for the Zeebe cluster to
converge across regions.

---

## Day-2 operations

| Task | Command |
|---|---|
| Verify the topology | `./procedure/check-cluster-topology.sh` |
| Activate a provisioned but empty region | `./procedure/activate-region.sh <slot>` |
| Handle a region loss | `./procedure/failover.sh <slot> [--unplanned]` |
| Bring a region back | `./procedure/failback.sh <slot> [--switch-writer]` |
| Probe the cross-region substrate | `./procedure/verify-cross-region-connectivity.sh` |
| Measure the write path to the database | `./procedure/measure-rdbms-latency.sh` |
| Diagnose cross-region networking | `./procedure/submariner/diagnose-submariner.sh` |

### Region loss

With three or more slots, `failover.sh` mostly **reports**: Zeebe keeps its
quorum and needs no intervention. Its real work is the database writer, and only
when the writer was in the lost region:

- **planned** — `failover-global-cluster`, a switchover with no data loss;
- **unplanned** — `remove-from-global-cluster`, which promotes a surviving
  member and loses whatever had not replicated yet.

`--drain-brokers` force-removes the lost brokers so that the surviving regions
run at full replication factor. It trades a partition reconfiguration for
durability and is worth it only for a long outage.

### Upgrades

Upgrade **one region at a time** and wait for the cluster to be healthy in
between. Upgrading several regions simultaneously risks losing quorum.

---

## Known limitations

- **Not covered by Camunda documentation or support.** The product documents two
  regions. Everything beyond that is exploratory.
- **No Management Identity**, hence **no Optimize** and no Web Modeler. The
  Orchestration Cluster ships its own Admin component; authentication is basic
  auth.
- **Optimize is impossible on RDBMS** regardless of the region count: it
  requires Elasticsearch or OpenSearch.
- **Database tier is active-standby.** Every region writes to one region's
  writer.
- **The slot count is immutable.** Growing from `N` to `N+1` slots renumbers
  every broker.
- **Connectors run in every region** and are not deduplicated. Outbound
  connector invocations must be idempotent.
- **Cross-region traffic is unencrypted in transit.** It crosses the AWS
  backbone on private addresses and never touches the internet, but there is no
  overlay providing IPsec. See "Why there is no encrypted overlay": an encrypted
  overlay and the VPC CNI cannot both own the pod ranges. If you need
  confidentiality in transit, terminate TLS in the workload or accept the
  operational cost of a different CNI.
- **Submariner is a single point of failure for discovery, not for traffic.**
  Losing Lighthouse stops new exports from propagating and new brokers from
  resolving their peers; it does not interrupt established connections, because
  it never carried them.
- **Broker startup DNS gate.** Brokers resolve their initial contact points once
  and hang on `NXDOMAIN`
  ([camunda/camunda#55038](https://github.com/camunda/camunda/issues/55038)).
  A temporary init container gates startup until clusterset DNS resolves; remove
  it once the upstream fix ships.
- **Backups are not wired up yet.** RDBMS backup and restore relies on
  continuous primary-storage backups plus a database-native backup; see
  [Backup and restore for RDBMS][rdbms-backup].

[rdbms-backup]: https://docs.camunda.io/docs/next/self-managed/operational-guides/backup-restore/rdbms/rdbms-backup/

---

## Regions used

| Slot | Region | Cleanup schedule |
|---|---|---|
| 0 | `eu-west-2` (London) | CI region, nightly |
| 1 | `eu-west-3` (Paris) | CI region, nightly |
| 2 | `eu-central-2` (Zurich) | CI region, nightly |
| 3 | `eu-south-1` (Milan) | Weekly work region, optional 4th slot |

`eu-central-2` and `eu-south-1` are AWS opt-in regions: they must be enabled on
the account before use, and their cleanup schedule is declared in
[infraex-common-config](https://github.com/camunda/infraex-common-config).

Aurora Global Database is not available in every region. `database_region_slots`
defaults to `[0, 1]` so that the database members live in London and Paris while
compute spans all three regions — which also demonstrates that the database
topology is independent of the compute topology.

Round trip times (indicative): London ↔ Paris ~7 ms, London ↔ Zurich ~20 ms,
Paris ↔ Zurich ~15 ms, all well inside the 100 ms budget.

---

## Related reference architectures

- `aws/kubernetes/eks-dual-region` — two regions, Elasticsearch, VPC peering and
  CoreDNS chaining. Documented and supported.
- `aws/openshift/rosa-hcp-dual-region` — two regions on OpenShift, Submariner via
  Red Hat ACM.
- `aws/containers/ecs-dual-region-fargate` — two regions on ECS Fargate with
  Aurora Global Database, the origin of the replication-agnostic RDBMS idea.
- `azure/kubernetes/aks-single-region-rdbms` — single region RDBMS secondary
  storage.
