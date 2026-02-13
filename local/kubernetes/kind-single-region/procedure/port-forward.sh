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
echo ""
echo "Services available at:"
echo "  - Zeebe gRPC API:    localhost:26500"
echo "  - Zeebe REST API:    localhost:8080   (Operate, Tasklist, Identity)"
echo "  - Optimize:          localhost:8083"
echo "  - Web Modeler:       localhost:8070"
echo "  - Connectors:        localhost:8088"
echo "  - Console:           localhost:8087"
echo "  - Identity:          localhost:8085"
echo "  - Keycloak:          keycloak-service:18080/auth (requires /etc/hosts entry)"
echo ""
echo "Login: admin / $(kubectl get secret camunda-credentials -n camunda -o jsonpath='{.data.identity-firstuser-password}' | base64 -d)"
echo ""

kubectl port-forward svc/camunda-zeebe-gateway 26500:26500 -n camunda &
kubectl port-forward svc/camunda-zeebe-gateway 8080:8080 -n camunda &
kubectl port-forward svc/camunda-optimize 8083:80 -n camunda &
kubectl port-forward svc/camunda-web-modeler-webapp 8070:80 -n camunda &
kubectl port-forward svc/camunda-connectors 8088:8080 -n camunda &
kubectl port-forward svc/camunda-console 8087:80 -n camunda &
kubectl port-forward svc/camunda-identity 8085:80 -n camunda &
kubectl port-forward svc/keycloak-service 18080:18080 -n camunda &
wait
