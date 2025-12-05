#!/bin/bash
set -euo pipefail

# Start port-forwarding for all Camunda components

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
