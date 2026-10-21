#!/usr/bin/env bash
#
# Init, plan and apply one layer of the ECS dual-region stack.
#
# Usage: apply-layer.sh <vpc|infra|app>
# Run from inside the layer's module directory.
#
# Required environment: TFSTATE_BUCKET, TFSTATE_REGION, TFSTATE_BASE_KEY.

set -euo pipefail

LAYER="${1:?usage: apply-layer.sh <vpc|infra|app>}"

: "${TFSTATE_BUCKET:?TFSTATE_BUCKET must be set}"
: "${TFSTATE_REGION:?TFSTATE_REGION must be set}"
: "${TFSTATE_BASE_KEY:?TFSTATE_BASE_KEY must be set}"

# infra/ and app/ read the layer above through terraform_remote_state at
# "<prefix><layer>/terraform.tfstate". The backend key must use the same shape
# or a layer would write its state where the next one will not look for it.
STATE_KEY="${TFSTATE_BASE_KEY}${LAYER}/terraform.tfstate"

echo "::group::terraform init (${LAYER} -> s3://${TFSTATE_BUCKET}/${STATE_KEY})"
terraform version
terraform init -no-color \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="key=${STATE_KEY}" \
    -backend-config="region=${TFSTATE_REGION}"
terraform validate -no-color
echo "::endgroup::"

echo "::group::terraform plan (${LAYER})"
terraform plan -no-color -var-file=terraform.tfvars -out "tf-${LAYER}.plan"
echo "::endgroup::"

echo "Applying ${LAYER} ..."
terraform apply -no-color "tf-${LAYER}.plan"
echo "Layer ${LAYER} applied."
