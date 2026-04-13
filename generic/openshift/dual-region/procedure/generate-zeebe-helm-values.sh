#!/bin/bash
set -euo pipefail

# Function to generate initial contact points
# Uses the headless service FQDN instead of individual broker pod addresses.
# Zeebe 8.9+ resolves all brokers behind a headless service name automatically,
# making this cluster-size independent.
generate_initial_contact() {
  local cluster_0=$1
  local namespace_0=$2
  local cluster_1=$3
  local namespace_1=$4
  local release=$5
  local port_number=${6:-26502}

  echo "${cluster_0}.${release}-zeebe.${namespace_0}.svc.clusterset.local:${port_number},${cluster_1}.${release}-zeebe.${namespace_1}.svc.clusterset.local:${port_number}"
}

# Function to generate Elasticsearch URL
# Note: defaults to elasticsearch-es-http (ClusterIP service).
# On OpenShift with Submariner, the ClusterIP service
# gets a stable ClusterSetIP for cross-cluster traffic, whereas the headless service
# relies on individual pod DNS records that are unreliable across cluster boundaries.
# This differs from the EKS dual-region setup which uses the headless service (elasticsearch-es-masters)
# because EKS VPN/peering only routes pod IPs, not ClusterIPs.
generate_exporter_elasticsearch_url() {
  local cluster_id=$1
  local namespace=$2
  local service_name=${ELASTICSEARCH_SERVICE_NAME:-elasticsearch-es-http}
  local port_number=${3:-9200}
  echo "http://${cluster_id}.${service_name}.${namespace}.svc.clusterset.local:${port_number}"
}

# Main script
cluster_0=${CLUSTER_0:-""}
cluster_1=${CLUSTER_1:-""}

namespace_0=${CAMUNDA_NAMESPACE_0:-""}
namespace_1=${CAMUNDA_NAMESPACE_1:-""}
namespace_0_failover=${CAMUNDA_NAMESPACE_0_FAILOVER:-""}
namespace_1_failover=${CAMUNDA_NAMESPACE_1_FAILOVER:-""}
helm_release_name=${CAMUNDA_RELEASE_NAME:-""}

mode="normal"
target_text="in the base Camunda Helm chart values file 'camunda-values.yml'"

# Check for deprecated ZEEBE_* environment variables
if [ -n "${ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS:-}" ]; then
    echo "WARNING: The environment variable ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS is deprecated."
    echo "         It was migrated in version 8.9 to CAMUNDA_CLUSTER_INITIALCONTACTPOINTS."
    echo "         The Helm Chart needs CAMUNDA_CLUSTER_INITIALCONTACTPOINTS to configure multi-region setups."
fi

zeebe_vars=$(env | grep '^ZEEBE_' || true)
if [ -n "$zeebe_vars" ]; then
    echo "WARNING: Detected ZEEBE_* environment variables which may be deprecated."
    echo "         As of version 8.9, many ZEEBE_* variables have been migrated to CAMUNDA_* equivalents."
    echo "         Please review and update your environment variables accordingly."
    echo
    echo "Detected variables:"
    while IFS= read -r line; do
        echo "  $line"
    done <<< "$zeebe_vars"
    echo
fi

if [[ $# -gt 0 ]]; then
  mode=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  if [[ "$mode" == "failover" ]]; then
    echo "Failover mode is enabled. The script will generate required values for failover."
    target_text="in the failover Camunda Helm chart values file '${REGION_SURVIVING:-""}/camunda-values-failover.yml' and in the base Camunda Helm chart values file 'camunda-values.yml'"
  elif [[ "$mode" == "failback" ]]; then
    echo "Failback mode is enabled. The script will generate required values for failback."
    target_text="in the failover Camunda Helm chart values file '${REGION_SURVIVING:-""}/camunda-values-failover.yml' and in the base Camunda Helm chart values file 'camunda-values.yml'"
  fi
fi

# Prompt user for missing values
if [[ "$mode" == "failover" ]]; then
  if [[ -z "$namespace_0_failover" ]]; then
    read -r -p "Enter the Kubernetes cluster namespace where Camunda 8 should be installed, in region 0 for failover mode: " namespace_0_failover
  fi
  if [[ -z "$namespace_1_failover" ]]; then
    read -r -p "Enter the Kubernetes cluster namespace where Camunda 8 should be installed, in region 1 for failover mode: " namespace_1_failover
  fi
fi

if [[ "$mode" == "failover" ]]; then
  read -r -p "Enter the region that was lost, values can either be 0 or 1: " lost_region
  if [[ "$lost_region" != "0" && "$lost_region" != "1" ]]; then
    echo "ERROR: Invalid region $lost_region provided for the lost region. Please provide either 0 or 1 as input value."
    exit 1
  fi
fi

if [[ "$namespace_0" == "$namespace_1" ]]; then
  echo "ERROR: Kubernetes namespaces for Camunda installations must be called differently"
  exit 1
fi

# Generate values
initial_contact=$(generate_initial_contact "$cluster_0" "$namespace_0" "$cluster_1" "$namespace_1" "$helm_release_name")
elastic0=$(generate_exporter_elasticsearch_url "$cluster_0" "$namespace_0")
elastic1=$(generate_exporter_elasticsearch_url "$cluster_1" "$namespace_1")

if [[ "$mode" == "failover" ]]; then
  if [[ "$lost_region" == "0" ]]; then
    elastic0=$(generate_exporter_elasticsearch_url "$cluster_1" "$namespace_1_failover")
    elastic1=$(generate_exporter_elasticsearch_url "$cluster_1" "$namespace_1")
  else
    elastic0=$(generate_exporter_elasticsearch_url "$cluster_0" "$namespace_0")
    elastic1=$(generate_exporter_elasticsearch_url "$cluster_0" "$namespace_0_failover")
  fi
fi

# Output results
echo -e "\nPlease use the following to change the existing environment variable CAMUNDA_CLUSTER_INITIALCONTACTPOINTS $target_text. It's part of the 'zeebe.env' path."
echo "- name: CAMUNDA_CLUSTER_INITIALCONTACTPOINTS"
echo "  value: $initial_contact"

export CAMUNDA_CLUSTER_INITIALCONTACTPOINTS="$initial_contact"

echo -e "\nPlease use the following to change the existing environment variable CAMUNDA_DATA_EXPORTERS_CAMUNDAREGION0_ARGS_CONNECT_URL $target_text. It's part of the 'zeebe.env' path."
echo "- name: CAMUNDA_DATA_EXPORTERS_CAMUNDAREGION0_ARGS_CONNECT_URL"
echo "  value: $elastic0"

export CAMUNDA_DATA_EXPORTERS_CAMUNDAREGION0_ARGS_CONNECT_URL="$elastic0"

echo -e "\nPlease use the following to change the existing environment variable CAMUNDA_DATA_EXPORTERS_CAMUNDAREGION1_ARGS_CONNECT_URL $target_text. It's part of the 'zeebe.env' path."
echo "- name: CAMUNDA_DATA_EXPORTERS_CAMUNDAREGION1_ARGS_CONNECT_URL"
echo "  value: $elastic1"

export CAMUNDA_DATA_EXPORTERS_CAMUNDAREGION1_ARGS_CONNECT_URL="$elastic1"

# Define the broker name of Zeebe Service
export REGION_0_ZEEBE_SERVICE_NAME="${cluster_0}.${helm_release_name}-zeebe.${namespace_0}.svc.clusterset.local"
export REGION_1_ZEEBE_SERVICE_NAME="${cluster_1}.${helm_release_name}-zeebe.${namespace_1}.svc.clusterset.local"

echo -e "\nPlease use the following to change the existing environment variable CAMUNDA_CLUSTER_NETWORK_ADVERTISEDHOST $target_text. It's part of the 'zeebe.env' path."
echo ""
echo "For region 0 (cluster $cluster_0):"
echo "- name: CAMUNDA_CLUSTER_NETWORK_ADVERTISEDHOST"
echo "  value: $REGION_0_ZEEBE_SERVICE_NAME"
echo ""
echo "For region 1 (cluster $cluster_1):"
echo "- name: CAMUNDA_CLUSTER_NETWORK_ADVERTISEDHOST"
echo "  value: $REGION_1_ZEEBE_SERVICE_NAME"
