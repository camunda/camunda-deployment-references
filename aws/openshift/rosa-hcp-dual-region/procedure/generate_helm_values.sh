#!/bin/bash

ZEEBE_SERVICE_NAME="$REGION_0_ZEEBE_SERVICE_NAME" DOLLAR="\$" envsubst < values-region-1.yml > generated-values-region-1.yml
cat generated-values-region-1.yml

ZEEBE_SERVICE_NAME="$REGION_1_ZEEBE_SERVICE_NAME" DOLLAR="\$" envsubst < values-region-2.yml > generated-values-region-2.yml
cat generated-values-region-2.yml
