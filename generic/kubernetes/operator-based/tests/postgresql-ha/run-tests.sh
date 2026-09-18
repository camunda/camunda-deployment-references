#!/bin/bash
# Integration test for the PostgreSQL reference architecture defaults.
#
# It pins the two properties the `instances: 2` and `walStorage` defaults exist for, neither
# of which a manifest lint can see:
#
#   1. the node hosting PostgreSQL can be drained, so a Kubernetes upgrade is not stuck on
#      the database;
#   2. a deployment still running the previous single-instance shape migrates to those
#      defaults in place, without losing its data.
#
# It also covers the PG_INSTANCES escape hatch, so the single-instance path that Kind and
# other memory-constrained environments take stays drainable too. Both branches of
# deploy.sh, with and without the override, run through deploy.sh itself rather than
# through a re-implementation of what it does.
#
# Needs a multi-node cluster: a switchover has nowhere to go on a single node. Creates its
# own Kind cluster by default.
#
# Environment variables:
#   SKIP_CLUSTER_CREATE - "true" reuses the current kubectl context instead of creating a
#                         Kind cluster. The context must point at a cluster with at least
#                         two schedulable nodes.
#   KEEP_CLUSTER        - "true" leaves the Kind cluster running for inspection.
#   CNPG_TIMEOUT        - seconds to wait for a cluster to reach its instance count (600).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSTGRESQL_DIR="$SCRIPT_DIR/../../postgresql"
KIND_CLUSTER_NAME="cnpg-ha-test"
HA_NAMESPACE="cnpg-ha"
SINGLE_NAMESPACE="cnpg-single"
SKIP_CLUSTER_CREATE=${SKIP_CLUSTER_CREATE:-false}
KEEP_CLUSTER=${KEEP_CLUSTER:-false}
CNPG_TIMEOUT=${CNPG_TIMEOUT:-600}

failures=0
checks=0

pass() {
    checks=$((checks + 1))
    echo "    ok   - $1"
}

fail() {
    checks=$((checks + 1))
    failures=$((failures + 1))
    echo "    FAIL - $1" >&2
}

assert_eq() {
    local expected=$1 actual=$2 what=$3
    if [[ "$expected" == "$actual" ]]; then
        pass "$what == $actual"
    else
        fail "$what: expected '$expected', got '$actual'"
    fi
}

scenario() {
    echo ""
    echo "=== $1 ==="
}

# shellcheck disable=SC2317,SC2329 # invoked indirectly, through the EXIT trap below
cleanup() {
    local exit_code=$?
    # A cordoned node outlives a failed run and silently breaks the next one, so uncordon
    # before anything else and never let the teardown itself fail the test.
    kubectl uncordon --all >/dev/null 2>&1 || true
    if [[ "$SKIP_CLUSTER_CREATE" != "true" && "$KEEP_CLUSTER" != "true" ]]; then
        echo ""
        echo "Deleting Kind cluster $KIND_CLUSTER_NAME"
        kind delete cluster --name "$KIND_CLUSTER_NAME" || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT

# Wait until a CloudNativePG cluster reports the expected number of ready instances.
# `kubectl wait --for=condition=Ready cluster` is satisfied while a second instance is still
# being cloned, so it cannot stand in for this.
#
# The fourth argument asks for the healthy phase on top of the count. It defaults to true,
# because a converged cluster reports both, and is passed false right after a drain, where
# one instance is deliberately down and the cluster is expected to stay degraded.
wait_ready_instances() {
    local cluster=$1 namespace=$2 expected=$3 require_healthy=${4:-true}
    local deadline=$((SECONDS + CNPG_TIMEOUT))
    local ready phase

    while [[ $SECONDS -lt $deadline ]]; do
        ready=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.readyInstances}' 2>/dev/null || echo "")
        phase=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [[ "$ready" == "$expected" ]] &&
            { [[ "$require_healthy" != "true" ]] || [[ "$phase" == "Cluster in healthy state" ]]; }; then
            echo "  $cluster: $ready/$expected ready (${phase:-unknown})"
            return 0
        fi
        echo "  $cluster: ${ready:-0}/$expected ready (${phase:-pending})"
        sleep 10
    done

    echo "ERROR: $cluster did not reach $expected ready instances within ${CNPG_TIMEOUT}s" >&2
    kubectl get cluster "$cluster" -n "$namespace" \
        -o custom-columns='NAME:.metadata.name,INSTANCES:.spec.instances,READY:.status.readyInstances,PHASE:.status.phase' >&2
    kubectl get pods,pvc -n "$namespace" -o wide >&2
    kubectl get events -n "$namespace" --sort-by=.lastTimestamp >&2 | tail -20
    return 1
}

# Ask the eviction API directly. This is the call kubectl drain issues in a loop, so it
# answers "would a drain be blocked here" without waiting out a drain timeout.
evict_is_allowed() {
    local pod=$1 namespace=$2
    local body
    body=$(printf '{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"%s","namespace":"%s"}}' "$pod" "$namespace")
    kubectl create -f - --raw "/api/v1/namespaces/$namespace/pods/$pod/eviction" <<< "$body" >/dev/null 2>&1
}

# Resolve the primary, waiting for one to exist. During a switchover no pod carries the
# primary role for a moment, and reading through it straight after a drain is how this test
# first flaked.
primary_pod() {
    local cluster=$1 namespace=$2
    local deadline=$((SECONDS + 120))
    local name

    while [[ $SECONDS -lt $deadline ]]; do
        name=$(kubectl get pod -n "$namespace" \
            -l "cnpg.io/cluster=$cluster,cnpg.io/instanceRole=primary" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "$name" ]]; then
            echo "$name"
            return 0
        fi
        sleep 5
    done

    echo "ERROR: $cluster has no primary in $namespace after 120s" >&2
    kubectl get pods -n "$namespace" -o wide >&2
    return 1
}

psql_local() {
    local pod=$1 namespace=$2 database=$3 sql=$4
    kubectl exec -n "$namespace" "$pod" -c postgres -- psql -U postgres -d "$database" -tAc "$sql"
}

has_symlinked_wal() {
    kubectl exec -n "$2" "$1" -c postgres -- test -L /var/lib/postgresql/data/pgdata/pg_wal
}

# Wait until the standby is actually streaming from the primary.
#
# This is not the same as the cluster reporting a healthy state. After the primary restarts
# to attach its WAL volume, the cluster can report two ready instances while the standby has
# not re-established streaming replication yet. A standby in that state is not a switchover
# candidate, so a drain started too early gets "Current primary is running on unschedulable
# node, but there are no valid candidates" from the operator and never completes.
wait_replica_streaming() {
    local cluster=$1 namespace=$2
    local deadline=$((SECONDS + CNPG_TIMEOUT))
    local state

    while [[ $SECONDS -lt $deadline ]]; do
        state=$(psql_local "$(primary_pod "$cluster" "$namespace")" "$namespace" postgres \
            "SELECT state FROM pg_stat_replication LIMIT 1;" 2>/dev/null || echo "")
        if [[ "$state" == "streaming" ]]; then
            echo "  $cluster: standby is streaming"
            return 0
        fi
        echo "  $cluster: standby not streaming yet (${state:-no connection})"
        sleep 5
    done

    echo "ERROR: $cluster has no streaming standby after ${CNPG_TIMEOUT}s" >&2
    return 1
}

if [[ "$SKIP_CLUSTER_CREATE" != "true" ]]; then
    echo "Creating Kind cluster $KIND_CLUSTER_NAME"
    kind create cluster --config "$SCRIPT_DIR/kind-cluster-config.yml"
    kubectl config use-context "kind-$KIND_CLUSTER_NAME"
fi

kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes -o wide

for namespace in "$HA_NAMESPACE" "$SINGLE_NAMESPACE"; do
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done

cd "$POSTGRESQL_DIR"

scenario "Scenario 1: PG_INSTANCES=1 keeps a constrained deployment drainable"

# This first deploy.sh call also installs the CloudNativePG operator, which every later
# scenario needs, and it exercises the override branch of the manifest rendering.
PG_INSTANCES=1 CLUSTER_FILTER=pg-keycloak CAMUNDA_NAMESPACE="$SINGLE_NAMESPACE" ./deploy.sh
wait_ready_instances pg-keycloak "$SINGLE_NAMESPACE" 1

assert_eq "1" "$(kubectl get cluster pg-keycloak -n "$SINGLE_NAMESPACE" -o jsonpath='{.spec.instances}')" \
    "the override reached the applied cluster"
assert_eq "false" "$(kubectl get cluster pg-keycloak -n "$SINGLE_NAMESPACE" -o jsonpath='{.spec.enablePDB}')" \
    "the override disabled the PodDisruptionBudget"
assert_eq "0" "$(kubectl get pdb -n "$SINGLE_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')" \
    "PodDisruptionBudget objects left to block a drain"

if evict_is_allowed pg-keycloak-1 "$SINGLE_NAMESPACE"; then
    pass "the single instance is evictable, so its node stays drainable"
else
    fail "the single instance is not evictable, so its node cannot be drained"
fi

# Tear this cluster down before the drain scenario runs, so the drain only has to deal with
# the cluster under test. Left in place, its single instance can land on the node drained
# later, where it is evicted and then stays Pending because that node is cordoned.
kubectl delete cluster pg-keycloak -n "$SINGLE_NAMESPACE" --ignore-not-found
kubectl delete namespace "$SINGLE_NAMESPACE" --ignore-not-found

scenario "Scenario 2: the previous single-instance shape pins its node"

# Reconstructed from the committed manifest rather than kept as a second fixture, so it
# tracks the real cluster definition instead of drifting from it. This is what a deployment
# created before these defaults still looks like today: one instance, PodDisruptionBudget
# left enabled, no dedicated WAL volume.
CLUSTER_FILTER=pg-identity CAMUNDA_NAMESPACE="$HA_NAMESPACE" ./set-secrets.sh
yq 'select(.metadata.name == "pg-identity") | .spec.instances = 1 | del(.spec.walStorage)' \
    postgresql-clusters.yml | kubectl apply -n "$HA_NAMESPACE" --server-side -f -
wait_ready_instances pg-identity "$HA_NAMESPACE" 1

assert_eq "1" "$(kubectl get pvc -n "$HA_NAMESPACE" --no-headers | wc -l | tr -d ' ')" \
    "volumes owned by the single instance"

if has_symlinked_wal pg-identity-1 "$HA_NAMESPACE"; then
    fail "pg_wal is already a symlink before walStorage is configured"
else
    pass "pg_wal lives inside PGDATA before walStorage is configured"
fi

if evict_is_allowed pg-identity-1 "$HA_NAMESPACE"; then
    fail "a single instance was evictable, so the PodDisruptionBudget no longer blocks a drain"
else
    pass "a single instance is not evictable, which is what stalls a node upgrade"
fi

scenario "Scenario 3: re-running deploy.sh migrates that deployment in place"

psql_local pg-identity-1 "$HA_NAMESPACE" identity \
    "CREATE TABLE migration_probe(note text); INSERT INTO migration_probe VALUES ('written before the migration');" \
    > /dev/null
data_pvc_uid_before=$(kubectl get pvc pg-identity-1 -n "$HA_NAMESPACE" -o jsonpath='{.metadata.uid}')

CLUSTER_FILTER=pg-identity CAMUNDA_NAMESPACE="$HA_NAMESPACE" ./deploy.sh
wait_ready_instances pg-identity "$HA_NAMESPACE" 2

assert_eq "$data_pvc_uid_before" \
    "$(kubectl get pvc pg-identity-1 -n "$HA_NAMESPACE" -o jsonpath='{.metadata.uid}')" \
    "the original data volume was kept rather than re-bootstrapped"
assert_eq "written before the migration" \
    "$(psql_local "$(primary_pod pg-identity "$HA_NAMESPACE")" "$HA_NAMESPACE" identity 'SELECT note FROM migration_probe;')" \
    "data written before the migration survived it"
assert_eq "2" "$(kubectl get pod -n "$HA_NAMESPACE" -l cnpg.io/cluster=pg-identity \
    -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')" \
    "distinct nodes hosting the two instances"

for pvc in pg-identity-1 pg-identity-1-wal pg-identity-2 pg-identity-2-wal; do
    assert_eq "Bound" \
        "$(kubectl get pvc "$pvc" -n "$HA_NAMESPACE" -o jsonpath='{.status.phase}' 2> /dev/null)" \
        "volume $pvc"
done

for pod in $(kubectl get pod -n "$HA_NAMESPACE" -l cnpg.io/cluster=pg-identity -o jsonpath='{.items[*].metadata.name}'); do
    if has_symlinked_wal "$pod" "$HA_NAMESPACE"; then
        pass "$pod moved pg_wal onto its dedicated volume"
    else
        fail "$pod still keeps pg_wal inside PGDATA"
    fi
done

scenario "Scenario 4: the node hosting the primary can be drained"

# The switchover the drain depends on needs a standby that is caught up, which lags the
# cluster reporting itself healthy.
wait_replica_streaming pg-identity "$HA_NAMESPACE"

primary_before=$(primary_pod pg-identity "$HA_NAMESPACE")
primary_node=$(kubectl get pod "$primary_before" -n "$HA_NAMESPACE" -o jsonpath='{.spec.nodeName}')
echo "  draining $primary_node, which hosts primary $primary_before"

if kubectl drain "$primary_node" --ignore-daemonsets --delete-emptydir-data --timeout=300s; then
    pass "the node hosting the primary drained"
else
    fail "the node hosting the primary could not be drained"
fi

wait_ready_instances pg-identity "$HA_NAMESPACE" 1 false
primary_after=$(primary_pod pg-identity "$HA_NAMESPACE")

if [[ "$primary_after" != "$primary_before" ]]; then
    pass "the primary moved to $primary_after"
else
    fail "the primary is still $primary_after on the drained node"
fi
assert_eq "written before the migration" \
    "$(psql_local "$primary_after" "$HA_NAMESPACE" identity 'SELECT note FROM migration_probe;')" \
    "the database still serves after the switchover"

kubectl uncordon "$primary_node"
wait_ready_instances pg-identity "$HA_NAMESPACE" 2

echo ""
if [[ "$failures" -eq 0 ]]; then
    echo "All $checks checks passed."
else
    echo "$failures of $checks checks failed." >&2
fi
exit "$((failures > 0 ? 1 : 0))"
