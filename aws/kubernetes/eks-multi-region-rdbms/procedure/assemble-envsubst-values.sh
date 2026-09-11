#!/bin/bash
set -euo pipefail

# Renders one values file per active region from helm-values/camunda-values.yml.
#
# Run after sourcing export_environment_prerequisites.sh and
# generate-zeebe-helm-values.sh:
#
#   . ./export_environment_prerequisites.sh
#   . ./generate-zeebe-helm-values.sh
#   ./assemble-envsubst-values.sh
#
# Output: generated-values-region-<slot>.yml

: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_CLUSTER_SIZE:?CAMUNDA_CLUSTER_SIZE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_PARTITION_COUNT:?CAMUNDA_PARTITION_COUNT must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REPLICATION_FACTOR:?CAMUNDA_REPLICATION_FACTOR must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RDBMS_USERNAME:?CAMUNDA_RDBMS_USERNAME must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RDBMS_URL:?CAMUNDA_RDBMS_URL must be set, e.g. from 'terraform output -raw camunda_rdbms_url'}"
: "${CAMUNDA_CLUSTER_INITIALCONTACTPOINTS:?CAMUNDA_CLUSTER_INITIALCONTACTPOINTS must be set, source generate-zeebe-helm-values.sh}"
: "${CAMUNDA_MULTIREGION_ZONES:?CAMUNDA_MULTIREGION_ZONES must be set, source generate-zeebe-helm-values.sh}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_TEMPLATE="${VALUES_TEMPLATE:-$SCRIPT_DIR/../helm-values/camunda-values.yml}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD}"

# `${DOLLAR}` escapes a literal `$` that must survive envsubst and reach the
# container at runtime (Kubernetes downward-API expansion and shell variables in
# the init container).
export DOLLAR='$'

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    zeebe_service_var="REGION_${i}_ZEEBE_SERVICE_NAME"
    : "${!zeebe_service_var:?${zeebe_service_var} must be set, source generate-zeebe-helm-values.sh}"

    read -r -a _zone_names <<<"${CAMUNDA_ZONE_NAMES:?CAMUNDA_ZONE_NAMES must be set, source export-terraform-outputs.sh}"

    CAMUNDA_REGION_ID="$i" \
        CAMUNDA_ZONE_NAME="${_zone_names[$i]}" \
        ZEEBE_SERVICE_NAME="${!zeebe_service_var}" \
        envsubst <"$VALUES_TEMPLATE" >"$OUTPUT_DIR/generated-values-region-${i}.yml"

    echo "Wrote $OUTPUT_DIR/generated-values-region-${i}.yml"
done
