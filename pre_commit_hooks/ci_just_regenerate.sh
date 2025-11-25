#!/usr/bin/env bash
# This hook runs 'just regenerate-golden-file-all' only in CI environments
# Note: CI will automatically fix this only for Renovate PRs

set -e

# Check if running in CI
if [ -n "$CI" ]; then
    echo "CI environment detected, running 'just regenerate-golden-file-all'..."
    if ! just regenerate-golden-file-all; then
        echo "Error: 'just regenerate-golden-file-all' failed"
        echo "Please run 'just regenerate-golden-file-all' locally and commit the changes"
        exit 1
    fi
else
    echo "Not in CI environment, skipping 'just regenerate-golden-file-all'"
fi
