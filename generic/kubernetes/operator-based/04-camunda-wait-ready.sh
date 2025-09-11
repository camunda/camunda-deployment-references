#!/bin/bash
set -euo pipefail

# Script to wait for Camunda Platform to be ready
# Usage: ./04-camunda-wait-ready.sh [namespace] [timeout_minutes]

NAMESPACE=${1:-camunda}
TIMEOUT_MINUTES=${2:-10}

echo "Waiting for Camunda Platform to be ready in namespace: $NAMESPACE"
echo "Timeout: $TIMEOUT_MINUTES minutes"

# Function to check if a deployment is ready
check_deployment_ready() {
    local deployment=$1
    local ready=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    if [ "$ready" = "$desired" ] && [ "$ready" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to check if a StatefulSet is ready
check_statefulset_ready() {
    local statefulset=$1
    local ready=$(kubectl get statefulset "$statefulset" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get statefulset "$statefulset" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    if [ "$ready" = "$desired" ] && [ "$ready" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Core components that need to be ready
DEPLOYMENTS=("camunda-identity" "camunda-operate" "camunda-tasklist" "camunda-optimize" "camunda-connectors")
STATEFULSETS=("camunda-zeebe" "camunda-zeebe-gateway")

# Optional components (check if they exist first)
OPTIONAL_DEPLOYMENTS=("camunda-web-modeler-webapp" "camunda-web-modeler-websockets" "camunda-web-modeler-restapi" "camunda-console")

# Calculate timeout in seconds
TIMEOUT_SECONDS=$((TIMEOUT_MINUTES * 60))
START_TIME=$(date +%s)

echo "Checking core components..."
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
        echo "❌ Timeout reached ($TIMEOUT_MINUTES minutes). Some components are not ready."
        exit 1
    fi

    ALL_READY=true

    # Check deployments
    for deployment in "${DEPLOYMENTS[@]}"; do
        if kubectl get deployment "$deployment" -n "$NAMESPACE" >/dev/null 2>&1; then
            if ! check_deployment_ready "$deployment"; then
                echo "⏳ Waiting for deployment $deployment to be ready..."
                ALL_READY=false
                break
            fi
        else
            echo "⚠️  Deployment $deployment not found, skipping..."
        fi
    done

    # Check StatefulSets
    if [ "$ALL_READY" = true ]; then
        for statefulset in "${STATEFULSETS[@]}"; do
            if kubectl get statefulset "$statefulset" -n "$NAMESPACE" >/dev/null 2>&1; then
                if ! check_statefulset_ready "$statefulset"; then
                    echo "⏳ Waiting for StatefulSet $statefulset to be ready..."
                    ALL_READY=false
                    break
                fi
            else
                echo "⚠️  StatefulSet $statefulset not found, skipping..."
            fi
        done
    fi

    # Check optional components if they exist
    if [ "$ALL_READY" = true ]; then
        for deployment in "${OPTIONAL_DEPLOYMENTS[@]}"; do
            if kubectl get deployment "$deployment" -n "$NAMESPACE" >/dev/null 2>&1; then
                if ! check_deployment_ready "$deployment"; then
                    echo "⏳ Waiting for optional deployment $deployment to be ready..."
                    ALL_READY=false
                    break
                fi
            fi
        done
    fi

    if [ "$ALL_READY" = true ]; then
        echo "✅ All Camunda Platform components are ready!"
        break
    fi

    # Show remaining time
    REMAINING=$((TIMEOUT_SECONDS - ELAPSED))
    echo "⏱️  Time remaining: $((REMAINING / 60))m$((REMAINING % 60))s"

    sleep 10
done

# Final status check
echo ""
echo "=== Final Component Status ==="
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/part-of=camunda-platform

echo ""
echo "=== Service Status ==="
kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/part-of=camunda-platform

echo ""
echo "✅ Camunda Platform is ready in namespace: $NAMESPACE"
