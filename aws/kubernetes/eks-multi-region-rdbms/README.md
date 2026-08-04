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

| Slot | Region | VPC / node CIDR | Service CIDR | Pod CIDR |
|---|---|---|---|---|
| 0 | eu-west-2 | `10.192.0.0/16` | `10.190.0.0/16` | `100.64.0.0/16` |
| 1 | eu-west-3 | `10.202.0.0/16` | `10.200.0.0/16` | `100.65.0.0/16` |
| 2 | eu-central-2 | `10.212.0.0/16` | `10.210.0.0/16` | `100.66.0.0/16` |
| 3 | eu-south-1 | `10.222.0.0/16` | `10.220.0.0/16` | `100.67.0.0/16` |

The Transit Gateway carries **the VPC and service CIDRs only**. Leaving the pod
CIDR out is deliberate; see the next section.

### Pod networking

This is the part that differs most from the other AWS references, and the part
that has to be right for anything else to work.

By default the AWS VPC CNI allocates pod addresses out of the node subnets, so
a pod address *is* a VPC address. That is what makes `eks-dual-region` simple:
pod traffic is routed natively by VPC peering, and CoreDNS forwarding is enough.

It cannot work here. Submariner installs node routes for every remote cluster
CIDR it is joined with, so that a packet addressed to a remote pod enters its
tunnel. When the pod range *is* the VPC range, those routes also cover the
remote **nodes** — including the gateway addresses the tunnels are themselves
built on — while the Transit Gateway still advertises the same prefix. The
result is not a clean failure: brokers resolve their peers, poll requests time
out, and no Raft quorum ever forms.

The OpenShift dual-region reference does not hit this because OVNKubernetes
gives pods a geneve overlay whose addresses the VPC never sees. This
architecture reproduces that separation on EKS with **VPC CNI custom
networking**:

| | Node subnets | Pod subnets |
|---|---|---|
| Range | `vpc_cidr_block`, the VPC primary CIDR | `pod_cidr_block`, a VPC **secondary** CIDR |
| Created by | the `eks-cluster` module | `terraform/clusters/pod-networking.tf` |
| Carries | nodes, load balancers, Aurora | pods only |
| Routed over the Transit Gateway | yes | **no** |
| Reached from another region by | Transit Gateway | Submariner tunnel |

Pod ranges come from `100.64.0.0/10` (RFC 6598 shared address space): outside
the RFC 1918 plan, so a corporate network peered in later cannot collide with
them.

The service CIDR stays on the Transit Gateway even though Submariner also
claims it. That is safe for a reason worth being explicit about: a service range
is virtual and has no interface in any VPC, so a route for it can never capture
a real endpoint the way a route for the node range does.

Two things follow, and both are load-bearing:

- `subctl join --clustercidr` is given the **pod** CIDR, not the VPC CIDR.
  Passing the VPC CIDR is what makes Submariner claim the routed range.
- pod CIDRs are still **distinct per region**. It is tempting to reuse one
  range everywhere since it is never routed between them, but Submariner runs
  without Globalnet: a prefix registered by two clusters cannot be resolved to
  one tunnel, and `subctl join` rejects it. The `regions` variable validates
  this.

A third constraint only shows up once the tunnels are already healthy. The VPC
CNI source-NATs every packet leaving the VPC to the node address, and a remote
pod range is by construction outside the local VPC. Left alone, a Zeebe
connection arrives in the remote cluster from a **node** address, while
Submariner routes and `security.tf` authorises **pod** addresses — so the
packets are dropped while `subctl show all` keeps reporting a healthy mesh, and
the only symptom is `Poll request to N failed ... connection timed out` in the
broker logs. `configure-vpc-cni-custom-networking.sh` therefore also sets
`AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS` to the remote pod and service ranges.
Preserving the source address is not a tuning choice: without Globalnet, the
pod address *is* how Submariner identifies a cluster.

The Kubernetes half of the change — the `aws-node` flags, the per-zone
`ENIConfig` objects and the node recycle that makes them take effect — lives in
`procedure/configure-vpc-cni-custom-networking.sh`. It has to run **before** the
Submariner gateways are labelled, because it replaces every node.

> [!NOTE]
> Custom networking removes the primary network interface from the pod address
> pool, which lowers the real maximum number of pods per node (for an
> `m6i.xlarge`, 58 to 44). The node groups here are far from that ceiling, so
> `max-pods` is left at the default. A production sizing should set it from
> `max-pods-calculator.sh --cni-custom-networking-enabled`.

### L4/L7: Submariner

[Submariner][submariner] provides cross-cluster service discovery and an
encrypted overlay. It is deployed **upstream** (`subctl deploy-broker` and
`subctl join`), not through the Red Hat ACM add-on used by the OpenShift
dual-region reference, because ACM is OpenShift-only.

- Cable driver **libreswan** (IPsec). Transit Gateway traffic crosses the AWS
  backbone unencrypted, so this is defence in depth, not decoration.
- `--air-gapped` and `--natt=false`: gateways reach each other over private
  addresses through the Transit Gateway, never over the internet.
- **Globalnet disabled**: CIDRs are already non-overlapping, which Transit
  Gateway requires anyway.
- One gateway node per cluster by default; raise
  `SUBMARINER_GATEWAY_NODES_PER_CLUSTER` for gateway HA.

Lighthouse publishes exported services as
`<clusterID>.<service>.<namespace>.svc.clusterset.local`. This is what lets the
architecture use **one namespace name in every cluster** instead of the
`N` namespaces replicated `N` times that CoreDNS stub forwarding would need.

Firewall rules are in `terraform/clusters/security.tf` and are written out
explicitly rather than "allow all between VPCs", because the port list is the
part a reader actually needs. Each rule also declares *which* remote range it
accepts, because Submariner preserves source addresses: a tunnel packet carries
the remote **node** address, a cross-region Zeebe packet carries the remote
**pod** address.

| Port | Protocol | Accepted from | Purpose |
|---|---|---|---|
| 4500 | UDP | node | IPsec NAT traversal |
| 4490 | UDP | node | NAT traversal discovery |
| 500 | UDP | node | IKE negotiation |
| — | ESP (IP 50) | node | Encrypted tunnel payload |
| 4800 | UDP | node | VXLAN pod traffic encapsulation |
| — | ICMP | node, pod | Gateway health check and `subctl diagnose` |
| 8080 | TCP | node, pod | Submariner metrics, Orchestration REST API |
| 26500-26502 | TCP | pod | Zeebe gateway, command API, Raft |
| 9600 | TCP | pod | Orchestration management API |
| 53 | TCP/UDP | pod | CoreDNS and Lighthouse |

Pairing every rule with every remote range instead would exceed the AWS limit of
60 inbound rules per security group at three regions; `checks.tf` asserts the
budget at plan time rather than letting the apply fail after the clusters exist.


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

# 5. Pod networking: move the pods off the routed node range.
#    Replaces every node, so it runs before the gateway labels.
./configure-vpc-cni-custom-networking.sh

# 6. Submariner
source ./submariner/install-subctl.sh
./submariner/label-gateway-nodes.sh
./submariner/deploy-broker.sh
./submariner/join-clusters.sh
./submariner/verify-submariner.sh

# 7. Substrate check, two minutes, before spending thirty on Camunda
./verify-cross-region-connectivity.sh

# 8. Camunda
./setup-namespaces.sh
./create-rdbms-secret.sh
. ./generate-zeebe-helm-values.sh
./assemble-envsubst-values.sh
./install-chart.sh
./submariner/export-services.sh

# 9. Verify
./check-cluster-topology.sh
```

Expect roughly 25 minutes for the EKS clusters, 15 for the Aurora Global
Database (both in parallel), 10 for the node recycle, 5 for Submariner and 10
for the Zeebe cluster to converge across regions.

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
- **Cross-region Raft is unencrypted at L3**; confidentiality comes from the
  Submariner IPsec tunnels, so a Submariner outage is a security event, not only
  an availability one.
- **Custom networking is applied after the cluster exists**, by a procedure that
  recycles every node. It is a one-off cost at bootstrap, but it means a freshly
  applied Terraform state is not yet usable: the pods are still on the routed
  node range until `configure-vpc-cni-custom-networking.sh` has run.
- **A `vpc-cni` addon upgrade reverts the custom networking flags.** The EKS
  addon owns the `aws-node` DaemonSet and is installed with
  `resolve_conflicts_on_update = OVERWRITE`, so it overwrites the two
  environment variables the procedure sets. Re-run the procedure after an
  upgrade; pinning the values in the addon's `configuration_values` is the
  production answer and is not wired up here.
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
