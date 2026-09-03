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
| Adding a region | Not possible | Possible: zones are named, not numbered |

---

## Contents

- [Topology](#topology)
- [Zones](#zones)
- [Zones vs active regions](#zones-vs-active-regions)
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
        zone "london"             zone "paris"            zone "zurich"
        ┌───────────────┐         ┌───────────────┐        ┌───────────────┐
        │ EKS           │         │ EKS           │        │ EKS           │
        │ zeebe london_0│         │ zeebe paris_0 │        │ zeebe zurich_0│
        │ zeebe london_1│         │ zeebe paris_1 │        │ zeebe zurich_1│
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
| `regions` (Terraform) | 3 | London, Paris, Zurich |
| `orchestration.multiregion.mode` | `zoned` | Zone-aware partitioning |
| `numberOfBrokers` per zone | 2 | Brokers deployed in that zone |
| `numberOfReplicas` per zone | 1 | One replica of every partition per zone |
| cluster size | 6 | Sum of `numberOfBrokers`, derived by the chart |
| replication factor | 3 | Sum of `numberOfReplicas`, derived by the chart |
| `orchestration.partitionCount` | 6 | One partition per broker |
| `database_region_slots` | `[0, 1]` | Aurora members, writer first |

Brokers are identified as `<zone>_<index>`, so the topology is readable from the
broker names — `paris_1` is the second broker in the Paris zone. There is no
node-ID arithmetic to reason about.

---

## Zones

The cluster is described as a list of **zones**, one per region, using the
`ZONE_AWARE` partitioning scheme:

```yaml
orchestration:
  multiregion:
    mode: zoned
    zone: paris          # the only per-region value
    zones:
      - {name: london, numberOfBrokers: 2, numberOfReplicas: 1, priority: 1000}
      - {name: paris,  numberOfBrokers: 2, numberOfReplicas: 1, priority: 900}
      - {name: zurich, numberOfBrokers: 2, numberOfReplicas: 1, priority: 800}
```

Each zone declares how many brokers it holds and how many replicas of every
partition live in it. `numberOfReplicas: 1` per zone means the replication
factor equals the zone count and **every zone holds exactly one replica of every
partition** — so losing a zone costs one replica out of N. A partition keeps its
majority while `N-1 > N/2`, true for every `N >= 3`:

| Zones | Replication factor | Zone losses tolerated |
|---|---|---|
| 2 | 2 | **0** |
| 3 | 3 | 1 |
| 4 | 4 | 1 |
| 5 | 5 | 2 |

Three zones is the smallest topology where losing one does not stop the engine.

**Priority skews Raft leadership.** Zone 0 has the highest, and that is not
cosmetic: it hosts the Aurora writer, and a partition leader co-located with the
writer avoids the inter-region round trip on every export flush. That cost is
measured — see [Day-2 operations](#day-2-operations) — and the Camunda
documentation calls out this exact use of priority for RDBMS secondary storage.

### Why not broker numbering

The chart offers two ways to tell a broker which region it is in, through
`orchestration.multiregion.mode`. One numbers the brokers and derives the region
from the number: with `orchestration.multiregion.regions`, a broker's region is
the parity of its node ID (`nodeId = ordinal * regions + regionId`). The `zoned`
mode names the region instead, and the name becomes part of the broker's
identity. This architecture sets `zoned`.

**This is a configuration choice, not an architecture.** A dual-region cluster
configured with zones is still a dual-region cluster: two regions, two
Elasticsearch exporters, the same secondary-storage setup and the same manual
failover when a region is lost. Nothing in the
[dual-region procedure](../eks-dual-region/README.md) changes because the brokers
are called `region-a_0` instead of `0`.

What the numbering does decide is what the cluster can do afterwards, and this is
why this architecture uses zones:

| Numbering by node ID | Naming by zone |
|---|---|
| Region count is baked into every broker's identity — changing it renumbers the whole cluster | Zones are named; the count is not encoded in an identity |
| `clusterSize` must divide evenly by the region count | Each zone declares its own broker count, so 2-2-1 is expressible |
| A broker's identity encodes arithmetic | Identity is `<zone>_<index>`, readable from the broker name |

Camunda documents the numbering as working for **exactly two regions**, with zone
awareness **required for three or more**. Zone awareness is the configuration to
use for a new deployment, and the reason is practical rather than editorial:
because the region count is part of broker identity under numbering, moving an
existing cluster onto zones renumbers its brokers, so the choice is effectively
made once, at bootstrap.

## Zones vs active regions

The zone list covers every zone the cluster will ever have; `active_region_count`
controls how many are actually deployed. Listing a zone before deploying it is
deliberate: the partition layout reserves its replicas, so each partition runs at
`N-1` of `N` — a majority — and the cluster forms and serves normally.

Activating that zone then only fills in replicas that were already reserved. No
broker is renumbered, no partition is redistributed and the regions already
running are left alone, which is what makes `activate-region.sh` non-disruptive.
The contact point list matters at bootstrap; once the cluster is formed a new
broker only has to reach one member, and the rest learn about it by gossip.

Leaving **two or more** zones empty is rejected by a `check` block in
`terraform/clusters/checks.tf`: every partition would lose its majority.

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

What this costs is less than it first appears. Removing the overlay does **not**
leave the traffic in clear text: AWS encrypts inter-region Transit Gateway
peering itself.

> Inter-Region gateway peering uses the same network infrastructure as VPC
> peering. Therefore traffic is encrypted using AES-256 encryption at the
> virtual network layer as it travels between Regions. Traffic is also encrypted
> using AES-256 encryption at the physical layer when it traverses network links
> that are outside of the physical control of AWS. As a result, traffic is
> double encrypted on network links outside the physical control of AWS.
>
> — [Transit gateway peering attachments][tgw-encryption]

The EC2 documentation states the same from the other direction: "All cross-Region
traffic that uses Amazon VPC peering and Transit Gateway peering is automatically
bulk-encrypted when it exits a Region", and "All traffic between AZs is
encrypted" ([Encryption in transit][ec2-encryption]).

What is actually given up is **control of the encryption**, not the encryption:
the keys are AWS-managed and the property is asserted by the provider rather
than verifiable from inside the cluster. Note also that the Nitro
instance-to-instance encryption listed in the same document does not apply here,
because it is void when "the traffic does not pass through a virtual network
device or service, such as a load balancer or a transit gateway".

If you need customer-managed keys or encryption you can demonstrate end to end,
see [Adding your own encryption](#adding-your-own-encryption).

[tgw-encryption]: https://docs.aws.amazon.com/vpc/latest/tgw/tgw-peering.html
[ec2-encryption]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/data-protection.html#encryption-transit

### Adding your own encryption

The encryption above is AWS-managed. If a control requires customer-managed keys
or encryption you can demonstrate end to end, the options in rough order of
cost:

| Option | Encrypts | Cost |
|---|---|---|
| **TLS in the workload** | The Camunda APIs it is enabled on | No infrastructure change; does not cover everything on the wire |
| **Cilium in ENI mode + WireGuard or IPsec** | All pod-to-pod traffic, transparently | Replaces the VPC CNI |
| **Site-to-site VPN instead of Transit Gateway peering** | Everything between regions | Your own IPsec keys, but per-tunnel throughput caps and an extra failure domain |

Cilium is the option that fits this architecture, and the reason is the same one
that removed the overlay: in ENI mode pod addresses stay ordinary VPC addresses,
so the Transit Gateway remains the only owner of the routes and encryption is
applied transparently underneath. It is the intersection of "encrypted with keys
you hold" and "no second owner of the pod ranges".

Reintroducing Submariner's connectivity component is **not** on this list. See
the section above for why it cannot coexist with the VPC CNI.

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
./register-kubecontexts.sh

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

`--drain-brokers` force-removes the lost zone, through
`DELETE /actuator/cluster/zones/<zone>`. One atomic change evicts its brokers and
drops the zone from the persisted partition distribution, so quorum stops
counting replicas that cannot answer. `failback.sh` puts it back with
`POST /actuator/cluster/zones/<zone>`, supplying the replica count, priority and
broker count from the same zone list the chart deploys.

> [!IMPORTANT]
> The re-add names the brokers by count. The endpoint expands `numberOfBrokers`
> into `<zone>_0 .. <zone>_<n-1>` itself, which is where the ids come from when
> the removal has left no membership to read them back from. That form needs an
> engine carrying [camunda/camunda#61775][add-zone-count], which reached
> `stable/8.10` **after `8.10.0-alpha5`**; an older build rejects the body. Older
> builds, and a zone returning with non-contiguous ids — two of its three
> brokers, say — take the explicit `{"brokers":["<zone>_0", ...]}` form, which
> stays supported.

[add-zone-count]: https://github.com/camunda/camunda/pull/61775

Whether you need it is a function of how many zones are left:

| Zones | After losing one | Draining |
|---|---|---|
| 2 | 1 replica of 2, no majority, processing stops | **Required.** Removing the zone restores a quorum the survivor can reach on its own |
| 3 or more | 2 replicas of 3, majority holds, processing continues | **Optional**, and usually not worth it for a zone expected back |

The reason to leave a zone in place is failback cost. Brokers that stayed members
rejoin and catch up from the Raft log; a removed zone has to be added back
explicitly, and its brokers start from nothing.

Because it is irreversible on a live cluster, rehearse it first:

```bash
./failover.sh <slot> --drain-brokers --dry-run
```

That reports the plan the API would execute and changes nothing, neither the
zone nor the database writer. `failback.sh` prints the body of its re-add before
sending it, so the return trip can be replayed the same way against
`?dryRun=true`.

That is not theory. Run `33055779396` passed both `TestMultiRegionRegionLoss` and
`TestMultiRegionFailback` on a three-zone cluster with no membership change at
all: `failover.sh` only read `GET /actuator/cluster`, and the region came back by
being redeployed.

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
- **The zone list is fixed at bootstrap in this architecture**, though zone
  awareness itself does not require that. Growing the list is a change to every
  region's values and has not been exercised here; the supported growth path is
  activating a zone that was declared up front.
- **Connectors run in every region** and are not deduplicated. Outbound
  connector invocations must be idempotent.
- **Encryption in transit is AWS-provided, not architecture-provided.** Traffic
  is encrypted — AES-256 bulk encryption when it leaves a Region over Transit
  Gateway peering, plus physical-layer encryption — but with AWS-managed keys
  and no way to verify it from inside the cluster. An encrypted overlay and the
  VPC CNI cannot both own the pod ranges, so the overlay is not available as a
  way to change that. See [Adding your own encryption](#adding-your-own-encryption)
  for the options if a control requires customer-managed keys.
- **Submariner is a single point of failure for discovery, not for traffic.**
  Losing Lighthouse stops new exports from propagating and new brokers from
  resolving their peers; it does not interrupt established connections, because
  it never carried them.
- **Broker startup DNS race.** A broker that starts before a cross-region peer
  is resolvable parks during startup, never binds 9600 and never recovers on its
  own ([camunda/camunda#55038](https://github.com/camunda/camunda/issues/55038)).
  Upstream closed that as fixed downstream and does not intend to change the
  product: the fix is to mark the initial contact points as **fully qualified**,
  with a trailing dot, so the resolver does not spend its budget walking the
  pod's search domains first. That is what `generate-zeebe-helm-values.sh` emits.

  The cross-region DNS gate in the Helm values predates that fix and is now
  belt-and-braces rather than the mechanism: it is fail-open, and with
  fully-qualified contact points it should resolve immediately. It is a
  candidate for removal once a run confirms the dot alone is sufficient —
  `eks-dual-region` carries the dot and no gate.
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
