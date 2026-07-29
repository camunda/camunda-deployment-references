#!/bin/bash
# Best-effort Submariner diagnostics. Never fails, so it can be wired into the
# `if: failure()` step of a workflow without masking the original error.
set +e

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"

    echo "=============================================================="
    echo "== Submariner diagnostics for $context"
    echo "=============================================================="

    echo "--- subctl show all"
    subctl show all --contexts "$context" 2>&1

    echo "--- submariner-operator pods"
    kubectl --context "$context" -n submariner-operator get pods -o wide 2>&1

    echo "--- gateway logs (last 200 lines)"
    kubectl --context "$context" -n submariner-operator logs -l app=submariner-gateway --tail=200 --prefix 2>&1

    echo "--- gateways and endpoints"
    kubectl --context "$context" get gateways.submariner.io,endpoints.submariner.io -A -o wide 2>&1

    echo "--- gateway-labelled nodes"
    kubectl --context "$context" get nodes -l submariner.io/gateway=true -o wide 2>&1

    echo "--- service exports / imports"
    kubectl --context "$context" get serviceexports.multicluster.x-k8s.io,serviceimports.multicluster.x-k8s.io -A -o wide 2>&1
done

echo "=============================================================="
echo "== Cross-cluster DNS resolution"
echo "=============================================================="

read -r -a cluster_ids <<<"${SUBMARINER_CLUSTER_IDS:-}"
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    for ((j = 0; j < CAMUNDA_ACTIVE_REGIONS; j++)); do
        [ "$i" -eq "$j" ] && continue
        target="${cluster_ids[$j]}.${CAMUNDA_RELEASE_NAME:-camunda}-zeebe.${CAMUNDA_NAMESPACE:-camunda}.svc.clusterset.local"
        echo "--- ${contexts[$i]} -> $target"
        kubectl --context "${contexts[$i]}" -n "${CAMUNDA_NAMESPACE:-camunda}" \
            run "submariner-dns-probe-$i-$j" --rm -i --restart=Never \
            --image=busybox:1.37 --command -- nslookup "$target" 2>&1
    done
done

exit 0
