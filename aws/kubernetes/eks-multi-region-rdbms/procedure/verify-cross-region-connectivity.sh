#!/bin/bash
set -euo pipefail

# Cross-region pod-to-pod connectivity probe.
#
#   ./verify-cross-region-connectivity.sh
#
# Answers one question in about two minutes: can a pod in region A reach a pod
# in region B, by name, over whatever substrate is configured?
#
# It exists because every connectivity failure in this architecture has so far
# been discovered at the end of a thirty-minute Camunda deployment, where the
# symptom (brokers not ready, HTTP 401 from the gateway) is several layers away
# from the cause. This isolates the substrate from Camunda entirely.
#
# Run it after Submariner is up and before installing the chart. It is also the
# fastest way to check a networking change without redeploying anything.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_CLUSTER_IDS:?SUBMARINER_CLUSTER_IDS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"

PROBE_IMAGE="${PROBE_IMAGE:-busybox:1.37}"
PROBE_PORT="${PROBE_PORT:-8080}"
PROBE_TIMEOUT="${PROBE_CONNECT_TIMEOUT:-10}"
PROBE_READY_TIMEOUT="${PROBE_READY_TIMEOUT:-120s}"
PROBE_IMPORT_TIMEOUT="${PROBE_IMPORT_TIMEOUT:-300}"
# Per path, so a slow record does not read as an unreachable one.
PROBE_RETRY_SECONDS="${PROBE_RETRY_SECONDS:-180}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
read -r -a cluster_ids <<<"$SUBMARINER_CLUSTER_IDS"

# This runs before the chart is installed, so the namespace it probes in may not
# exist yet. Created here rather than assumed, so the script stands on its own as
# a diagnostic; setup-namespaces.sh creates the same thing the same way.
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    kubectl --context "${contexts[$i]}" create namespace "$CAMUNDA_NAMESPACE" \
        --dry-run=client -o yaml | kubectl --context "${contexts[$i]}" apply -f - >/dev/null
done

cleanup() {
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        kubectl --context "${contexts[$i]}" -n "$CAMUNDA_NAMESPACE" \
            delete serviceexport.multicluster.x-k8s.io connectivity-probe --ignore-not-found --wait=false >/dev/null 2>&1 || true
        kubectl --context "${contexts[$i]}" -n "$CAMUNDA_NAMESPACE" \
            delete statefulset connectivity-probe --ignore-not-found --wait=false >/dev/null 2>&1 || true
        kubectl --context "${contexts[$i]}" -n "$CAMUNDA_NAMESPACE" \
            delete service connectivity-probe --ignore-not-found --wait=false >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

###############################################################################
# Deploy one responder per region                                             #
#                                                                             #
# A headless service and a StatefulSet, matching how Zeebe is addressed: the   #
# per-pod DNS records are what brokers actually dial, and they are published   #
# differently from a ClusterIP service. Probing a ClusterIP would pass while   #
# Zeebe still fails.                                                          #
###############################################################################

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    echo "Deploying the probe responder in ${cluster_ids[$i]} ($context)"

    kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: connectivity-probe
spec:
  clusterIP: None
  selector:
    app: connectivity-probe
  ports:
    - name: http
      port: ${PROBE_PORT}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: connectivity-probe
spec:
  serviceName: connectivity-probe
  replicas: 1
  selector:
    matchLabels:
      app: connectivity-probe
  template:
    metadata:
      labels:
        app: connectivity-probe
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - name: responder
          image: ${PROBE_IMAGE}
          command:
            - /bin/sh
            - -c
            - |
              while true; do
                printf 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok' | nc -l -p ${PROBE_PORT}
              done
          ports:
            - containerPort: ${PROBE_PORT}
EOF
done

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    kubectl --context "${contexts[$i]}" -n "$CAMUNDA_NAMESPACE" \
        rollout status statefulset/connectivity-probe --timeout="$PROBE_READY_TIMEOUT"
done

###############################################################################
# Publish the responders to the ClusterSet                                    #
#                                                                             #
# Lighthouse only resolves what has been exported. Without this the probe      #
# reports "the name does not resolve" in every direction and blames discovery, #
# which is true but says nothing about the substrate it is meant to test.      #
#                                                                             #
# The ServiceExport object is created directly rather than through `subctl     #
# export service`, so the procedure needs nothing on PATH but kubectl.         #
###############################################################################

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    echo "Exporting the probe responder of ${cluster_ids[$i]} to the ClusterSet"

    kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" apply -f - <<EOF
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: connectivity-probe
EOF
done

echo "Waiting for the ServiceImports to be published ..."
deadline=$((SECONDS + PROBE_IMPORT_TIMEOUT))
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    while ! kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" \
        get serviceimport connectivity-probe >/dev/null 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: no ServiceImport for connectivity-probe on $context after ${PROBE_IMPORT_TIMEOUT}s." >&2
            echo "       Lighthouse is not publishing exports, so the probe cannot say anything" >&2
            echo "       about routing. Check the submariner-lighthouse-agent logs." >&2
            exit 1
        fi
        sleep 5
    done
done

# Lighthouse writes the DNS records shortly after the ServiceImport object.
sleep 15

###############################################################################
# Probe every ordered pair                                                    #
###############################################################################

failures=0
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    for ((j = 0; j < CAMUNDA_ACTIVE_REGIONS; j++)); do
        [ "$i" -eq "$j" ] && continue

        # The per-pod clusterset name, which is the form Zeebe dials. Trailing
        # dot for the same reason the contact points carry one: without it the
        # resolver walks the pod's search domains first, and a record Lighthouse
        # has not published yet turns into several cached negatives instead of
        # one, which is what the retry below exists to survive.
        target="connectivity-probe-0.${cluster_ids[$j]}.connectivity-probe.${CAMUNDA_NAMESPACE}.svc.clusterset.local."
        echo "--> ${cluster_ids[$i]} -> ${cluster_ids[$j]}"

        # Retried rather than attempted once. Lighthouse publishes the per-pod
        # records shortly after the ServiceImport, and CoreDNS caches negative
        # answers, so a single attempt reports a propagation delay as a routing
        # failure -- which it did, and cost a full run to work out.
        reachable=false
        path_deadline=$((SECONDS + PROBE_RETRY_SECONDS))
        while true; do
            if kubectl --context "${contexts[$i]}" -n "$CAMUNDA_NAMESPACE" \
                exec statefulset/connectivity-probe -- \
                timeout "$PROBE_TIMEOUT" nc -z -w "$PROBE_TIMEOUT" "$target" "$PROBE_PORT" >/dev/null 2>&1; then
                reachable=true
                break
            fi
            [ "$SECONDS" -ge "$path_deadline" ] && break
            sleep 5
        done

        if [ "$reachable" = true ]; then
            echo "    reachable"
            continue
        fi

        failures=$((failures + 1))
        echo "    UNREACHABLE after ${PROBE_RETRY_SECONDS}s"

        # Separate name resolution from reachability: they fail for completely
        # different reasons and the fix differs entirely.
        if kubectl --context "${contexts[$i]}" -n "$CAMUNDA_NAMESPACE" \
            exec statefulset/connectivity-probe -- nslookup "$target" >/dev/null 2>&1; then
            echo "    the name resolves, so this is a routing problem, not discovery."
            echo "    Check that the pod CIDR is claimed by exactly one of Submariner"
            echo "    and the Transit Gateway routes. In practice: the pods must be in"
            echo "    the 100.64.0.0/10 range, and 'subctl show all' must report the pod"
            echo "    and service CIDRs, never the VPC CIDR."
            echo "    See ../README.md, section 'Pod networking'."

        else
            echo "    the name does not resolve, so this is a discovery problem."
            echo "    Check the ServiceExports and that Lighthouse published a"
            echo "    ServiceImport: ./submariner/export-services.sh"
        fi
    done
done

echo
if [ "$failures" -ne 0 ]; then
    echo "$failures cross-region path(s) unreachable." >&2
    exit 1
fi
echo "Every cross-region path is reachable."
