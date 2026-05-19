#!/bin/bash
set -euo pipefail

# Generate a kubeconfig for the RBC team using the rbc-admin service account
# This kubeconfig can be shared with the team for direct cluster access
#
# Prerequisites:
#   - kubectl configured with admin access to both clusters
#   - rbc-admin-access.yml already applied on both clusters
#
# Usage:
#   ./generate-rbc-kubeconfig.sh <cluster-name>
#   Example: ./generate-rbc-kubeconfig.sh rbc-benchmark-edr-us-east-1

CLUSTER_NAME="${1:?Usage: $0 <cluster-name> (e.g., rbc-benchmark-edr-us-east-1)}"
NAMESPACE="kube-system"
SA_NAME="rbc-admin"
KUBECONFIG_FILE="kubeconfig-${CLUSTER_NAME}.yml"

echo "Generating kubeconfig for cluster: ${CLUSTER_NAME}"

# Get the API server endpoint
API_SERVER=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${CLUSTER_NAME}\")].cluster.server}")
if [[ -z "${API_SERVER}" ]]; then
    echo "Error: Could not find cluster '${CLUSTER_NAME}' in current kubeconfig"
    echo "Available contexts:"
    kubectl config get-contexts -o name
    exit 1
fi

# Get CA data
CA_DATA=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${CLUSTER_NAME}\")].cluster.certificate-authority-data}")

# Get the service account token
TOKEN=$(kubectl --context="${CLUSTER_NAME}" get secret "${SA_NAME}-token" -n "${NAMESPACE}" -o jsonpath='{.data.token}' | base64 -d)

if [[ -z "${TOKEN}" ]]; then
    echo "Error: Could not get token for service account '${SA_NAME}'"
    echo "Make sure rbc-admin-access.yml has been applied:"
    echo "  kubectl --context=${CLUSTER_NAME} apply -f manifests/rbc-admin-access.yml"
    exit 1
fi

# Generate the kubeconfig
cat > "${KUBECONFIG_FILE}" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${API_SERVER}
      certificate-authority-data: ${CA_DATA}
contexts:
  - name: ${CLUSTER_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      user: rbc-admin
      namespace: kube-system
current-context: ${CLUSTER_NAME}
users:
  - name: rbc-admin
    user:
      token: ${TOKEN}
EOF

echo "Kubeconfig written to: ${KUBECONFIG_FILE}"
echo ""
echo "Share this file with the RBC team. They can use it with:"
echo "  export KUBECONFIG=${KUBECONFIG_FILE}"
echo "  kubectl get nodes"
