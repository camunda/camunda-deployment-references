#!/bin/bash
set -euo pipefail

# Add hosts entries for camunda.example.com (requires sudo)

echo "Adding hosts entries (requires sudo)..."

grep -q "^127.0.0.1[[:space:]]*camunda.example.com$" /etc/hosts || echo "127.0.0.1 camunda.example.com" | sudo tee -a /etc/hosts
grep -q "^127.0.0.1[[:space:]]*zeebe-camunda.example.com$" /etc/hosts || echo "127.0.0.1 zeebe-camunda.example.com" | sudo tee -a /etc/hosts

echo "Hosts entries added."
