# Reproducing the Zeebe cold-start cross-region DNS hang on Kind

Local, single-machine reproduction of
[camunda/camunda#55038](https://github.com/camunda/camunda/issues/55038)
— *"Broker startup hangs indefinitely when cross-region peers are not yet
DNS-resolvable (cold multi-region start)"* — using a single
[Kind](https://kind.sigs.k8s.io/) cluster, no cloud account and no Submariner.

> **Status:** proposed reproduction scenario. The **startup hang** (issue steps
> 1–3) is reproduced and validated end-to-end on Kind on both the 8.7 standalone
> broker and the 8.9 unified image. See
> [What this does / does not reproduce](#what-this-does-and-does-not-reproduce)
> for the exact fidelity boundary versus the production report.

## The bug in one paragraph

On a cold multi-region deploy, a Zeebe broker that starts **before** its
cross-region peers are DNS-resolvable parks during `BrokerStartupProcess` at the
cluster-topology initialization step. The pod stays `0/1 Running`, the management
port **9600 never binds** (readiness probe = connection refused), and the cluster
topology never forms. In the field this is triggered by Submariner/Lighthouse
publishing the `*.svc.clusterset.local` records asynchronously, but it is **not
Submariner-specific**: any configured peer that becomes resolvable slightly
*after* the broker starts (slow cross-cluster DNS, CoreDNS warm-up, `ExternalName`
lag, …) can hit the same hang.

## How a single Kind cluster reproduces it

We do not need two clusters or Submariner — we only need a broker that **dials a
peer by a name that is `NXDOMAIN` at startup** and resolvable later:

| Production (ROSA HCP + Submariner)                          | This Kind model                                                                 |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Brokers dial peers via `*.svc.clusterset.local`            | Same — brokers advertise & dial `*.svc.clusterset.local` names                  |
| Submariner Lighthouse serves `clusterset.local` records    | A **CoreDNS `rewrite`** maps `*.svc.clusterset.local` → `*.svc.cluster.local`    |
| Lighthouse publishes cross-region records **asynchronously** | We apply that rewrite **after** the brokers have already started (the cold race) |
| `clusterSize: 8`, `replicationFactor: 4`, 2 regions        | `clusterSize: 2`, `replicationFactor: 2` — two brokers, one per "region"         |

Before the rewrite is applied, every `clusterset.local` name is `NXDOMAIN`, so the
brokers start into the exact unresolved window that wedges them in the field.

## Prerequisites

- Docker (running)
- [`kind`](https://kind.sigs.k8s.io/) and `kubectl`

```bash
kind version
kubectl version --client
```

## Step 1 — Create the Kind cluster

```bash
kind create cluster --name camunda-repro-55038 --image kindest/node:v1.34.0
kubectl config use-context kind-camunda-repro-55038
```

## Step 2 — Deploy two brokers that dial peers over `clusterset.local`

This StatefulSet uses the exact image from the issue's reproduction table
(`camunda/zeebe:8.7.29`). The readiness probe is a bare **TCP check on 9600**,
because the bug is literally *"port 9600 never binds"* — so `Ready` ⇔ the broker
finished startup. Both brokers start in **parallel** (a cold multi-region start),
and they advertise/dial `*.svc.clusterset.local` names which are **`NXDOMAIN`** at
this point (no CoreDNS rewrite yet).

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: camunda
---
# Headless service. publishNotReadyAddresses=true so brokers can discover each
# other's pod records *before* they are Ready (how Zeebe forms quorum on a cold start).
apiVersion: v1
kind: Service
metadata:
  name: zeebe
  namespace: camunda
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app: zeebe
  ports:
    - { name: gateway, port: 26500 }
    - { name: command, port: 26501 }
    - { name: internal, port: 26502 }
    - { name: monitoring, port: 9600 }
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: zeebe
  namespace: camunda
spec:
  serviceName: zeebe
  replicas: 2
  podManagementPolicy: Parallel   # both brokers start at once, like a cold multi-region start
  selector:
    matchLabels:
      app: zeebe
  template:
    metadata:
      labels:
        app: zeebe
    spec:
      terminationGracePeriodSeconds: 5
      containers:
        - name: zeebe
          image: camunda/zeebe:8.7.29
          imagePullPolicy: IfNotPresent
          # Derive nodeId + advertised host from the pod ordinal, then exec the broker.
          # The advertised host is a *.svc.clusterset.local name (as in a Submariner
          # multi-region setup), NOT the in-cluster cluster.local name, so peer
          # resolution depends on the faked clusterset DNS we publish in Step 4.
          command: ["/bin/sh", "-c"]
          args:
            - |
              export ZEEBE_BROKER_CLUSTER_NODEID="${HOSTNAME##*-}"
              export ZEEBE_BROKER_NETWORK_ADVERTISEDHOST="${HOSTNAME}.zeebe.camunda.svc.clusterset.local"
              echo "nodeId=${ZEEBE_BROKER_CLUSTER_NODEID} advertisedHost=${ZEEBE_BROKER_NETWORK_ADVERTISEDHOST}"
              exec /usr/local/zeebe/bin/broker
          env:
            - { name: ZEEBE_BROKER_CLUSTER_CLUSTERSIZE,       value: "2" }
            - { name: ZEEBE_BROKER_CLUSTER_PARTITIONSCOUNT,   value: "2" }
            - { name: ZEEBE_BROKER_CLUSTER_REPLICATIONFACTOR, value: "2" }
            # The cross-"region" contact point: a clusterset.local name that is
            # NXDOMAIN until the CoreDNS rewrite is applied in Step 4.
            - { name: ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS, value: "zeebe.camunda.svc.clusterset.local:26502" }
            - { name: ZEEBE_BROKER_NETWORK_HOST,   value: "0.0.0.0" }
            - { name: ZEEBE_BROKER_GATEWAY_ENABLE, value: "true" }
            - { name: ZEEBE_LOG_LEVEL,             value: "INFO" }
            - { name: JAVA_TOOL_OPTIONS,           value: "-Xms512m -Xmx512m" }
          ports:
            - { containerPort: 9600,  name: monitoring }
            - { containerPort: 26501, name: command }
            - { containerPort: 26502, name: internal }
          # The bug is "9600 never binds" → a bare TCP check is the cleanest signal:
          # port open => Ready, hung broker => connection refused => 0/1 Running.
          readinessProbe:
            tcpSocket: { port: 9600 }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
          resources:
            requests: { cpu: 200m, memory: 768Mi }
            limits:   { cpu: "2",  memory: 1280Mi }
          volumeMounts:
            - { name: data, mountPath: /usr/local/zeebe/data }
      volumes:
        - name: data
          emptyDir: {}
EOF
```

## Step 3 — Observe the hang (the bug)

```bash
kubectl -n camunda get pods -w
```

Both pods stay `0/1 Running` indefinitely:

```text
NAME      READY   STATUS    RESTARTS   AGE
zeebe-0   0/1     Running   0          5m9s
zeebe-1   0/1     Running   0          5m9s
```

Confirm the three signature symptoms:

```bash
# 1. Port 9600 never opens → readiness probe is refused
kubectl -n camunda describe pod zeebe-0 | grep -i "Readiness probe failed"
#   Warning  Unhealthy  ...  Readiness probe failed: dial tcp 10.244.0.5:9600: connect: connection refused

# 2. Startup is parked at the cluster-topology init step — and goes no further
kubectl -n camunda logs zeebe-0 | tail -3
#   io.camunda.zeebe.broker.system - Starting broker 0 version 8.7.29
#   io.camunda.zeebe.broker.system - Startup Cluster Services
#   io.camunda.zeebe.broker.system - Startup Cluster Topology Manager   <-- last line, hung here

# 3. The clusterset contact point is NXDOMAIN, while the same name under
#    cluster.local resolves fine (so only the cross-region name is unresolved)
kubectl -n camunda exec zeebe-0 -- getent hosts zeebe.camunda.svc.clusterset.local ; echo "exit=$?"   # exit=2 (NXDOMAIN)
kubectl -n camunda exec zeebe-0 -- getent hosts zeebe.camunda.svc.cluster.local    ; echo "exit=$?"   # exit=0 (resolves)
```

The park at **`Startup Cluster Topology Manager`** matches the issue's leading
suspect: dynamic cluster-configuration / topology initialization waiting to reach
peers it cannot resolve
([`ClusterConfigurationInitializer`](https://github.com/camunda/camunda/blob/ca255e8ea2a72894bffc529b70f4eaa8aef06b34/zeebe/dynamic-config/src/main/java/io/camunda/zeebe/dynamic/config/ClusterConfigurationInitializer.java)),
reached from the single startup join in
[`Broker.internalStart`](https://github.com/camunda/camunda/blob/ca255e8ea2a72894bffc529b70f4eaa8aef06b34/zeebe/broker/src/main/java/io/camunda/zeebe/broker/Broker.java#L124-L126).

> A pod restart at this point does **not** help: the fresh broker hits the same
> `NXDOMAIN` and parks again. The gate is DNS resolvability, not a one-off glitch.

## Step 4 — Publish the clusterset DNS (Submariner/Lighthouse catching up)

Apply a CoreDNS `rewrite` so `*.svc.clusterset.local` resolves to the in-cluster
`*.svc.cluster.local` records, then restart CoreDNS. Doing this **after** the
brokers started is the cold-start race: the names become resolvable too late.

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        # Simulate Submariner/Lighthouse: resolve *.svc.clusterset.local via the
        # in-cluster *.svc.cluster.local records.
        rewrite stop {
            name suffix .svc.clusterset.local .svc.cluster.local answer auto
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
EOF

kubectl -n kube-system rollout restart deployment coredns
kubectl -n kube-system rollout status  deployment coredns --timeout=60s
```

Verify the name now resolves:

```bash
kubectl -n camunda exec zeebe-0 -- getent hosts zeebe.camunda.svc.clusterset.local
#   10.244.0.5      zeebe.camunda.svc.clusterset.local
#   10.244.0.6      zeebe.camunda.svc.clusterset.local
```

Within ~1 minute the brokers complete startup, bind 9600 and become Ready:

```bash
kubectl -n camunda get pods
#   NAME      READY   STATUS    RESTARTS   AGE
#   zeebe-0   1/1     Running   0          12m
#   zeebe-1   1/1     Running   0          12m

kubectl -n camunda exec zeebe-0 -- wget -qO- http://localhost:9600/actuator/health/readiness
#   {"status":"UP","components":{"brokerReady":{"status":"UP"}}}

kubectl -n camunda logs zeebe-0 | grep -E "Transition to LEADER on term 1 completed|recovered, marking it as healthy" | tail -3
#   ... Transition to LEADER on term 1 completed
#   ... Partition-1 recovered, marking it as healthy
#   ... Partition-2 recovered, marking it as healthy
```

## Variant: per-pod names lag the headless name (the exact production trigger)

Steps 2–4 wedge the broker by making *every* `clusterset.local` name `NXDOMAIN`.
The field failure is subtler — and is why the workaround gates on **per-pod** names.
With Submariner the **headless** ServiceImport name
(`zeebe.camunda.svc.clusterset.local`) is published first, so the broker *discovers*
it has a peer, but the peer's **advertised per-pod** name
(`zeebe-1.zeebe.camunda.svc.clusterset.local`) is still `NXDOMAIN` when the broker
dials it — and topology init never completes.

Reproduce that exact split: use the **same** Corefile as Step 4 but replace the
`rewrite` line so only the headless name resolves, then cold-restart the brokers:

```bash
# In the Step 4 ConfigMap, swap the single rewrite line for an exact match:
#     rewrite name exact zeebe.camunda.svc.clusterset.local zeebe.camunda.svc.cluster.local answer auto
kubectl -n kube-system rollout restart deployment coredns
kubectl -n camunda delete pod zeebe-0 zeebe-1     # cold-restart into the split
```

They stay `0/1 Running` with 9600 closed, parked at the same `Startup Cluster
Topology Manager` step — now *visibly* failing to reach the discovered peer by its
advertised name:

```bash
kubectl -n camunda exec zeebe-0 -- getent hosts zeebe.camunda.svc.clusterset.local         ; echo $?  # 0  headless resolves
kubectl -n camunda exec zeebe-0 -- getent hosts zeebe-1.zeebe.camunda.svc.clusterset.local ; echo $?  # 2  per-pod NXDOMAIN

kubectl -n camunda logs zeebe-0 | grep -E "Failed to probe|ConnectionClosed" | tail -2
#   ...swim.probe - 0 - Failed all probes of Member{id=1, address=zeebe-1.zeebe.camunda.svc.clusterset.local:26502 ...}. Marking as suspect.
#   ...MessagingException$ConnectionClosed: Channel ... for address zeebe-1.zeebe.camunda.svc.clusterset.local:26502 was closed unexpectedly ...
```

This is the closest match to the field trigger and directly motivates the per-pod
DNS gate. Restore the Step 4 blanket rewrite (per-pod names resolve) and the
brokers recover on their own — see the fidelity note below.

## What this does and does not reproduce

**Reproduced and validated on Kind (the hard part):** the **startup hang** itself.
A broker that starts while a configured `*.svc.clusterset.local` name is `NXDOMAIN`
parks during `BrokerStartupProcess` at `Startup Cluster Topology Manager`, never
binds 9600, and stays `0/1 Running` — issue #55038 **steps 1–3** and the
*"Current behavior"* symptoms. Validated on **both** the 8.7 standalone broker
(`camunda/zeebe:8.7.29`) and the 8.9 unified image (`camunda/camunda:8.9.5` + a real
Elasticsearch — see [the unified-image section](#reproduce-on-the-unified-image-8810)),
and in **two** DNS conditions: (A) every clusterset name `NXDOMAIN` (Steps 2–4), and
(B) the more faithful split where the headless name resolves but per-pod names are
`NXDOMAIN` (the Variant above). On 8.9 the broker logs the **exact** error from the
issue while dialing the peer's advertised per-pod name:

```text
io.netty.resolver.dns.DnsErrorCauseException: Query failed with NXDOMAIN
  Failed to resolve 'zeebe-1.zeebe.camunda.svc.clusterset.local'
```

**Not reproduced by this minimal single-cluster model:** the production-reported
**permanent** hang. In *every* variant, once the missing name became resolvable the
broker **re-resolved and finished startup on its own within ~20–60 s — no pod
restart needed** (`0` restarts, `Transition to LEADER … completed`, 9600 `UP`). The
field report (ROSA HCP + Submariner, `clusterSize 8` / `RF 4`) is that the broker
stays wedged **even after** the names resolve, and only `kubectl delete pod`
recovers it.

So this scenario reliably reproduces the **trigger and the hang**; turning it into
the **permanent** hang is the open question. Two hypotheses were **tested here and
ruled out**:

- **JVM negative-DNS cache — ruled out.** Pinning the JVM negative cache to forever
  (`-Dnetworkaddress.cache.negative.ttl=-1 -Dsun.net.inetaddr.negative.ttl=-1`) did
  **not** prevent recovery — the broker still re-resolved and reached Ready in ~20 s.
  The failing/recovering lookups come from **Netty's own resolver**
  (`io.netty.resolver.dns`), which keeps its own non-caching negative cache and
  ignores the JVM security property.
- **8.9/8.10 discovery path — ruled out.** 8.9.5 (`DynamicDiscoveryProvider`)
  self-heals exactly like 8.7.29 (`BootstrapDiscoveryProvider`), so the wedge is not
  specific to one discovery path/version.

The remaining leading hypothesis — **not reproducible in a 2-broker model** — is the
**full-scale cold-start path**: the dynamic cluster-configuration consensus
(`ClusterConfigurationInitializer` Gossip/Sync) across **8 brokers / RF 4** stretched
over two regions, and/or Submariner Lighthouse's specific DNS behavior (intermittent
`SERVFAIL` / never-resolves rather than a clean `NXDOMAIN`→resolve transition).
Pinning the exact blocking line upstream is the way to settle it.

## Version mapping

The same hang affects 8.7 → 8.10. This repro uses the standalone broker
(`camunda/zeebe`) for a clean, ES-free, well-known-env reproduction; on 8.8+ the
broker ships inside the unified `camunda/camunda` image and the contact-point env
var was renamed:

| Line | Broker image                | Contact-point env var                       |
| ---- | --------------------------- | ------------------------------------------- |
| 8.7  | `camunda/zeebe:8.7.29`      | `ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS` |
| 8.8  | `camunda/camunda:8.8.24`    | `ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS` |
| 8.9  | `camunda/camunda:8.9.5`     | `CAMUNDA_CLUSTER_INITIALCONTACTPOINTS`      |
| 8.10 | `camunda/camunda:8.10.0-alpha2` | `CAMUNDA_CLUSTER_INITIALCONTACTPOINTS`  |

## Reproduce on the unified image (8.8–8.10)

The standalone `camunda/zeebe` broker above is the simplest repro. To reproduce on
the current line, swap in the unified `camunda/camunda` image — with two differences
(both validated on 8.9.5):

1. **It hard-requires a secondary storage.** Without one the app exits `255` (~5 min)
   and crash-loops instead of hanging, and the broker-only shortcuts both fail-fast:
   `CAMUNDA_DATA_SECONDARYSTORAGE_TYPE=none` → *"Basic Authentication is not supported
   when secondary storage is disabled"*, and `CAMUNDA_SECURITY_AUTHENTICATION_METHOD=none`
   → *"unsupported authentication method: none"*. So deploy a single-node Elasticsearch
   (the version the matching chart bundles, e.g. `8.18.0` for 8.9) on `cluster.local`
   and point the broker at it — the app context then starts and the broker hangs
   **indefinitely** at topology init. ES is local infra (always resolvable), so the
   only thing that hangs is the cross-region peer lookup.
2. **Config is under `camunda.cluster.*`** (env `CAMUNDA_CLUSTER_*`) and the broker
   binary is `/usr/local/camunda/bin/camunda`:

```yaml
image: camunda/camunda:8.9.5            # or 8.10.x
command: ["/bin/sh", "-c"]
args:
  - |
    export CAMUNDA_CLUSTER_NODEID="${HOSTNAME##*-}"
    export CAMUNDA_CLUSTER_NETWORK_ADVERTISEDHOST="${HOSTNAME}.zeebe.camunda.svc.clusterset.local"
    exec /usr/local/camunda/bin/camunda
env:
  - { name: CAMUNDA_CLUSTER_SIZE,                            value: "2" }
  - { name: CAMUNDA_CLUSTER_PARTITIONCOUNT,                  value: "2" }
  - { name: CAMUNDA_CLUSTER_REPLICATIONFACTOR,              value: "2" }
  - { name: CAMUNDA_CLUSTER_INITIALCONTACTPOINTS,           value: "zeebe.camunda.svc.clusterset.local:26502" }
  - { name: CAMUNDA_CLUSTER_NETWORK_HOST,                   value: "0.0.0.0" }
  - { name: CAMUNDA_DATA_SECONDARYSTORAGE_TYPE,             value: "elasticsearch" }
  - { name: CAMUNDA_DATA_SECONDARYSTORAGE_ELASTICSEARCH_URL, value: "http://elasticsearch.camunda.svc.cluster.local:9200" }
```

Everything else — the split-DNS CoreDNS rewrite, the `tcpSocket:9600` readiness
probe, the hang, and the self-heal once DNS resolves — is identical to the
standalone repro.

## Deploy-layer workarounds (already in this repo)

These mitigate the symptom at the deployment layer; none belong in the product.
Both are implemented for the OpenShift dual-region reference architecture:

- **DNS-gate initContainer** — blocks broker startup until every per-pod contact
  point resolves (`getent hosts`), so the broker never starts into the unresolved
  window:
  [`generic/openshift/dual-region/helm-values/values-base.yml`](../../../generic/openshift/dual-region/helm-values/values-base.yml)
  (`initContainers: wait-clusterset-dns`).
- **Self-heal restart** — deletes any broker pod stuck `Running`-but-not-`Ready`
  past a threshold so the StatefulSet recreates it:
  [`generic/openshift/dual-region/procedure/check-deployment-ready.sh`](../../../generic/openshift/dual-region/procedure/check-deployment-ready.sh).

## Cleanup

```bash
kind delete cluster --name camunda-repro-55038
```

## Links

- Issue: [camunda/camunda#55038](https://github.com/camunda/camunda/issues/55038)
- Hang point: [`Broker.internalStart`](https://github.com/camunda/camunda/blob/ca255e8ea2a72894bffc529b70f4eaa8aef06b34/zeebe/broker/src/main/java/io/camunda/zeebe/broker/Broker.java#L124-L126)
- Suspected blocker: [`ClusterConfigurationInitializer`](https://github.com/camunda/camunda/blob/ca255e8ea2a72894bffc529b70f4eaa8aef06b34/zeebe/dynamic-config/src/main/java/io/camunda/zeebe/dynamic/config/ClusterConfigurationInitializer.java)
