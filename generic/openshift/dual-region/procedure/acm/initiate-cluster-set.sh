#!/bin/bash

# AWS OpenShift specific requirement to ensure CA store is trusted
oc --context "$CLUSTER_1_NAME" apply -f klusterlet-global-config.yml || true # ignore if e.g. on non AWS

# local-cluster is the default name for the hub cluster and is by default already registered
# we need to add it to the same clusterset and label it for submariner
oc --context "$CLUSTER_1_NAME" label managedclusters local-cluster "cluster.open-cluster-management.io/clusterset=oc-clusters" --overwrite
oc --context "$CLUSTER_1_NAME" label managedclusters local-cluster "cluster.open-cluster-management.io/submariner-agent=true" --overwrite

# Import second cluster
SUB2_TOKEN=$(oc --context "$CLUSTER_2_NAME" whoami -t)
CLUSTER_2_API=$(oc config view --minify --context "$CLUSTER_2_NAME" --raw -o json | jq -r '.clusters[].cluster.server')

CLUSTER_NAME="$CLUSTER_2_NAME" envsubst < managed-cluster.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

CLUSTER_NAME="$CLUSTER_2_NAME" CLUSTER_TOKEN="$SUB2_TOKEN" CLUSTER_API="$CLUSTER_2_API" envsubst < auto-import-cluster-secret.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

CLUSTER_NAME="$CLUSTER_2_NAME" envsubst < klusterlet-config.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

oc --context "$CLUSTER_1_NAME" get managedclusters
# NAME            HUB ACCEPTED   MANAGED CLUSTER URLS                                 JOINED   AVAILABLE   AGE
# cl-oc-2         true           https://api.cl-oc-2.5egh.p3.openshiftapps.com:443    True     True        50s
# local-cluster   true           https://api.cl-oc-1.f70c.p3.openshiftapps.com:443   True     True        36m
