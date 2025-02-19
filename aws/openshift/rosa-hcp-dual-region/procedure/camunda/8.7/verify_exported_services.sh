#!/bin/bash

oc --context "$CLUSTER_1_NAME" describe ServiceExport -n "$CAMUNDA_NAMESPACE_1"
oc --context "$CLUSTER_2_NAME" describe ServiceExport -n "$CAMUNDA_NAMESPACE_2"
