#!/usr/bin/env bash
# This hook runs 'go mod tidy' only in CI environments
# Note: CI will automatically fix this only for Renovate PRs

set -e

# Check if running in CI
if [ -n "$CI" ]; then
    echo "CI environment detected, running 'go mod tidy'..."
    if ! go mod tidy; then
        echo "Error: 'go mod tidy' failed"
        echo "Please run 'go mod tidy' locally and commit the changes"
        exit 1
    fi
else
    echo "Not in CI environment, skipping 'go mod tidy'"
fi
