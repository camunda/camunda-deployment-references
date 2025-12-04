#!/bin/bash
set -euo pipefail

# Start port-forwarding for all Camunda components

echo "Starting port-forwards (Ctrl+C to stop)..."
echo ""
echo "Component                URL                              Description"
echo "─────────────────────────────────────────────────────────────────────────────────"
echo "Zeebe Gateway (gRPC)     localhost:26500                  Process deployment and execution"
echo "Zeebe Gateway (HTTP)     http://localhost:8080/           Zeebe REST API"
echo "Operate                  http://localhost:8080/operate    Monitor process instances"
echo "Tasklist                 http://localhost:8080/tasklist   Complete user tasks"
echo "Optimize                 http://localhost:8083            Process analytics"
echo "Web Modeler              http://localhost:8070            Design and deploy processes"
echo "Connectors               http://localhost:8085            External system integrations"
echo "Console                  http://localhost:8087            Manage clusters and APIs"
echo "Identity                 http://localhost:8080/identity   User and permission management for the orchestration cluster"
echo "Management Identity      http://localhost:18081           User and permission management"
echo "Keycloak                 http://localhost:18080           Authentication server"
echo ""

kubectl port-forward svc/camunda-zeebe-gateway 26500:26500 -n camunda &
kubectl port-forward svc/camunda-zeebe-gateway 8080:8080 -n camunda &
kubectl port-forward svc/camunda-optimize 8083:80 -n camunda &
kubectl port-forward svc/camunda-web-modeler-webapp 8070:80 -n camunda &
kubectl port-forward svc/camunda-connectors 8085:8080 -n camunda &
kubectl port-forward svc/camunda-console 8087:80 -n camunda &
kubectl port-forward svc/camunda-management-identity 18081:80 -n camunda &
kubectl port-forward svc/camunda-keycloak 18080:80 -n camunda &
wait
