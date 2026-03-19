#!/bin/bash

oc --context "$CLUSTER_0" describe ServiceExport -n "$CAMUNDA_NAMESPACE_0"
oc --context "$CLUSTER_1" describe ServiceExport -n "$CAMUNDA_NAMESPACE_1"
