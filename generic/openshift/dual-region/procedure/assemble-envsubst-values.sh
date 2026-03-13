#!/bin/bash

ZEEBE_SERVICE_NAME="$CLUSTER_1_REGION_ZEEBE_SERVICE_NAME" DOLLAR="\$" envsubst < values-region-0.yml > generated-values-region-0.yml
cat generated-values-region-0.yml

ZEEBE_SERVICE_NAME="$CLUSTER_2_REGION_ZEEBE_SERVICE_NAME" DOLLAR="\$" envsubst < values-region-1.yml > generated-values-region-1.yml
cat generated-values-region-1.yml
