#!/bin/bash
set -euo pipefail

# Emits the region-dependent Camunda settings that cannot be hardcoded in the
# Helm values, then exports them so that assemble-envsubst-values.sh can
# substitute them.
#
# Two values are produced:
#
#   CAMUNDA_CLUSTER_INITIALCONTACTPOINTS
#       One entry per ACTIVE region, pointing at the headless Zeebe service of
#       that region through Submariner Lighthouse. Zeebe resolves a headless
#       clusterset name to every broker pod IP of the exporting cluster, so the
#       list stays independent of the number of brokers per region.
#
#   REGION_<slot>_ZEEBE_SERVICE_NAME
#       Suffix of the advertised host of each broker. The chart default
#       (`<pod>.<service>.<namespace>.svc`) only resolves inside its own
#       cluster.
#
# Contact points intentionally cover only the active regions: a slot that has
# not been deployed yet has no DNS record, and listing it would make every
# broker wait on the startup DNS gate for nothing.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_CLUSTER_IDS:?SUBMARINER_CLUSTER_IDS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"

INTERNAL_PORT="${CAMUNDA_CLUSTER_INTERNAL_PORT:-26502}"

read -r -a cluster_ids <<<"$SUBMARINER_CLUSTER_IDS"

contact_points=""
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    fqdn="${cluster_ids[$i]}.${CAMUNDA_RELEASE_NAME}-zeebe.${CAMUNDA_NAMESPACE}.svc.clusterset.local"

    export "REGION_${i}_ZEEBE_SERVICE_NAME=$fqdn"

    if [ -z "$contact_points" ]; then
        contact_points="${fqdn}:${INTERNAL_PORT}"
    else
        contact_points="${contact_points},${fqdn}:${INTERNAL_PORT}"
    fi
done

export CAMUNDA_CLUSTER_INITIALCONTACTPOINTS="$contact_points"

echo "CAMUNDA_CLUSTER_INITIALCONTACTPOINTS=$CAMUNDA_CLUSTER_INITIALCONTACTPOINTS"
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    varname="REGION_${i}_ZEEBE_SERVICE_NAME"
    echo "${varname}=${!varname}"
done
