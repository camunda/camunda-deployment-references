#!/bin/bash
set -euo pipefail

# Start port-forwarding for all Camunda components

# Cleanup function to kill all background port-forward processes
cleanup() {
    echo ""
    echo "Stopping all port-forwards..."
    # Kill all background jobs started by this script
    jobs -p | xargs -r kill 2>/dev/null || true
    # Also kill any kubectl port-forward processes that might be orphaned
    pkill -P $$ 2>/dev/null || true
    exit 0
}

# Register cleanup function to run on script exit (Ctrl+C, kill, or normal exit)
trap cleanup EXIT INT TERM

echo "Starting port-forwards (Ctrl+C to stop)..."

kubectl port-forward svc/camunda-zeebe-gateway 26500:26500 -n camunda &
kubectl port-forward svc/camunda-zeebe-gateway 8080:8080 -n camunda &
kubectl port-forward svc/camunda-optimize 8083:80 -n camunda &
kubectl port-forward svc/camunda-web-modeler-webapp 8070:80 -n camunda &
kubectl port-forward svc/camunda-connectors 8085:8080 -n camunda &
kubectl port-forward svc/camunda-console 8087:80 -n camunda &
kubectl port-forward svc/camunda-identity 18081:80 -n camunda &
kubectl port-forward svc/camunda-keycloak 18080:8080 -n camunda &
wait
