#!/bin/bash
set -euo pipefail

# Add hosts entries for camunda.example.com (requires sudo)

echo "Adding hosts entries (requires sudo)..."

grep -q "camunda.example.com" /etc/hosts || echo "127.0.0.1 camunda.example.com" | sudo tee -a /etc/hosts
grep -q "zeebe-camunda.example.com" /etc/hosts || echo "127.0.0.1 zeebe-camunda.example.com" | sudo tee -a /etc/hosts

echo "Hosts entries added."
