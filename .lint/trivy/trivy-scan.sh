#!/bin/bash
set -euxo pipefail

# list of the folders that we want to parse, only if a README.md exists and no .trivy_ignore
echo "Scanning terraform files in aws dir with trivy:"
trivy config --config .lint/trivy/trivy.yaml --ignorefile .trivyignore --skip-dirs aws/ec2/test/fixtures aws
