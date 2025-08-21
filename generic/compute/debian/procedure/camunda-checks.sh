#!/bin/bash
set -o pipefail

# Executed on remote host
SCRIPT_STATUS_OUTPUT=0

check_service() {
    local url=$1
    local retries=3
    local delay=15
    local response

    echo "[INFO] Checking service on url $url..."

    for ((i=1; i<=retries; i++)); do
        response=$(curl -s -o /dev/null -w "%{http_code}" "$url")

        if [ "$response" -eq 200 ]; then
            echo "[OK] Service on url $url is available."
            return 0
        else
            echo "[FAIL] Service on url $url is not available (HTTP status code: $response)."
        fi

        if [ "$i" -lt "$retries" ]; then
            echo "[INFO] Retrying in $delay seconds..."
            sleep $delay
        fi
    done

    if [ "$response" -ne 200 ]; then
        echo "[FAIL][res=$response] Service on url $url is not available after $retries retries."
        if [[ "$url" =~ "health" ]]; then
            curl -s "$url"
        fi
        SCRIPT_STATUS_OUTPUT=1
    fi
}

check_service_running() {
    local service_name=$1

    if systemctl is-active --quiet "$service_name"; then
        echo "[OK] The service '$service_name' is running."
    else
        echo "[FAIL] The service '$service_name' is not running."
        SCRIPT_STATUS_OUTPUT=2
    fi
}

check_service 127.0.0.1:8080/operate
check_service 127.0.0.1:8080/tasklist
check_service 127.0.0.1:9600/actuator/health
check_service 127.0.0.1:9090/actuator/health

check_service_running camunda.service
check_service_running camunda-connectors.service

if [ "$SCRIPT_STATUS_OUTPUT" -ne 0 ]; then
    echo "[FAIL] At least one of the tests failed." 1>&2
    exit $SCRIPT_STATUS_OUTPUT
else
    echo "[OK] All test passed."
fi
