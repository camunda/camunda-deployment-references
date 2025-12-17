#!/bin/bash

# =============================================================================
# Create Backup PVC
# =============================================================================
# Creates a PersistentVolumeClaim for storing backup data during migration
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../0-set-environment.sh" 2>/dev/null || true

echo "Creating backup PVC in namespace: $CAMUNDA_NAMESPACE"

# Create PVC manifest
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${BACKUP_PVC_NAME}
  namespace: ${CAMUNDA_NAMESPACE}
  labels:
    app.kubernetes.io/name: migration-backup
    app.kubernetes.io/component: storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${BACKUP_STORAGE_SIZE}
EOF

# Wait for PVC to be bound
echo "Waiting for PVC to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
    pvc/"${BACKUP_PVC_NAME}" \
    -n "$CAMUNDA_NAMESPACE" \
    --timeout=120s || {
    echo "Warning: PVC not yet bound. This may be normal for dynamic provisioning."
    echo "The PVC will be bound when the first pod uses it."
}

echo ""
echo "Backup PVC created successfully!"
echo "  Name: ${BACKUP_PVC_NAME}"
echo "  Size: ${BACKUP_STORAGE_SIZE}"
echo "  Namespace: ${CAMUNDA_NAMESPACE}"
