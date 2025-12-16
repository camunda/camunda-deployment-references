#!/bin/bash

# Function to generate initial contact points
generate_initial_contact() {
  local cluster_0=$1
  local namespace_0=$2
  local cluster_1=$3
  local namespace_1=$4
  local release=$5
  local count=$6
  local port_number=${7:-26502}
  local result=()

  for ((i = 0; i < count / 2; i++)); do
    result+=("${release}-zeebe-${i}.${cluster_0}.${release}-zeebe.${namespace_0}.svc.clusterset.local:${port_number}")
    result+=("${release}-zeebe-${i}.${cluster_1}.${release}-zeebe.${namespace_1}.svc.clusterset.local:${port_number}")
  done

  IFS=","; echo "${result[*]}"; unset IFS
}

# Function to generate Elasticsearch URL
generate_exporter_elasticsearch_url() {
  local cluster_id=$1
  local namespace=$2
  local release=$3
  local port_number=${4:-9200}
  echo "http://${cluster_id}.${release}-elasticsearch-master-hl.${namespace}.svc.clusterset.local:${port_number}"
}

# Main script
cluster_0=${CLUSTER_1_NAME:-""}
cluster_1=${CLUSTER_2_NAME:-""}

namespace_0=${CAMUNDA_NAMESPACE_1:-""}
namespace_1=${CAMUNDA_NAMESPACE_2:-""}
namespace_0_failover=${CAMUNDA_NAMESPACE_1_FAILOVER:-""}
namespace_1_failover=${CAMUNDA_NAMESPACE_2_FAILOVER:-""}
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

if [[ -z "$ZEEBE_CLUSTER_SIZE" ]]; then
  read -r -p "Enter Zeebe cluster size (total number of Zeebe brokers in both Kubernetes clusters) [or set ZEEBE_CLUSTER_SIZE beforehand] (recommended value: 8): " ZEEBE_CLUSTER_SIZE
fi

# Convert to integer
cluster_size=$((ZEEBE_CLUSTER_SIZE))

if (( cluster_size % 2 != 0 )); then
  echo "ERROR: Cluster size $cluster_size is an odd number and not supported in a multi-region setup (must be an even number)"
  exit 1
fi
if (( cluster_size < 4 )); then
  echo "ERROR: Cluster size $cluster_size is too small and should be at least 4. A multi-region setup is not recommended for a small cluster size."
  exit 1
fi
if [[ "$namespace_0" == "$namespace_1" ]]; then
  echo "ERROR: Kubernetes namespaces for Camunda installations must be called differently"
  exit 1
fi

# Generate values
initial_contact=$(generate_initial_contact "$cluster_0" "$namespace_0" "$cluster_1" "$namespace_1" "$helm_release_name" "$cluster_size")
elastic0=$(generate_exporter_elasticsearch_url "$cluster_0" "$namespace_0" "$helm_release_name")
elastic1=$(generate_exporter_elasticsearch_url "$cluster_1" "$namespace_1" "$helm_release_name")

if [[ "$mode" == "failover" ]]; then
  if [[ "$lost_region" == "0" ]]; then
    elastic0=$(generate_exporter_elasticsearch_url "$cluster_1" "$namespace_1_failover" "$helm_release_name")
    elastic1=$(generate_exporter_elasticsearch_url "$cluster_1" "$namespace_1" "$helm_release_name")
  else
    elastic0=$(generate_exporter_elasticsearch_url "$cluster_0" "$namespace_0" "$helm_release_name")
    elastic1=$(generate_exporter_elasticsearch_url "$cluster_0" "$namespace_0_failover" "$helm_release_name")
  fi
fi

# Output results
echo -e "\nPlease use the following to change the existing environment variable CAMUNDA_CLUSTER_INITIALCONTACTPOINTS $target_text. It's part of the 'zeebe.env' path."
echo "- name: CAMUNDA_CLUSTER_INITIALCONTACTPOINTS"
echo "  value: $initial_contact"

export CAMUNDA_CLUSTER_INITIALCONTACTPOINTS="$initial_contact"

echo -e "\nPlease use the following to change the existing environment variable ZEEBE_BROKER_EXPORTERS_CAMUNDAREGION0_ARGS_CONNECT_URL $target_text. It's part of the 'zeebe.env' path."
echo "- name: ZEEBE_BROKER_EXPORTERS_CAMUNDAREGION0_ARGS_CONNECT_URL"
echo "  value: $elastic0"

export ZEEBE_BROKER_EXPORTERS_CAMUNDAREGION0_ARGS_CONNECT_URL="$elastic0"

echo -e "\nPlease use the following to change the existing environment variable ZEEBE_BROKER_EXPORTERS_CAMUNDAREGION1_ARGS_CONNECT_URL $target_text. It's part of the 'zeebe.env' path."
echo "- name: ZEEBE_BROKER_EXPORTERS_CAMUNDAREGION1_ARGS_CONNECT_URL"
echo "  value: $elastic1"

export ZEEBE_BROKER_EXPORTERS_CAMUNDAREGION1_ARGS_CONNECT_URL="$elastic1"

# Define the broker name of Zeebe Service
export REGION_0_ZEEBE_SERVICE_NAME="${cluster_0}.${helm_release_name}-zeebe.${namespace_0}.svc.clusterset.local"
export REGION_1_ZEEBE_SERVICE_NAME="${cluster_1}.${helm_release_name}-zeebe.${namespace_1}.svc.clusterset.local"

echo -e "\nPlease use the following to change the existing environment variable ZEEBE_BROKER_NETWORK_ADVERTISEDHOST $target_text. It's part of the 'zeebe.env' path."
echo ""
echo "For region 0 (cluster $cluster_0):"
echo "- name: ZEEBE_BROKER_NETWORK_ADVERTISEDHOST"
echo "  value: $REGION_0_ZEEBE_SERVICE_NAME"
echo ""
echo "For region 1 (cluster $cluster_1):"
echo "- name: ZEEBE_BROKER_NETWORK_ADVERTISEDHOST"
echo "  value: $REGION_1_ZEEBE_SERVICE_NAME"
