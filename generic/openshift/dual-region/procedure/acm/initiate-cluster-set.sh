#!/bin/bash

# Import the first cluster
SUB1_TOKEN=$(oc --context "$CLUSTER_1_NAME" whoami -t)
CLUSTER_1_API=$(oc config view --minify --context "$CLUSTER_1_NAME" --raw -o json | jq -r '.clusters[].cluster.server')

# for the first cluster, the cluster name is hardcoded on purpose
CLUSTER_NAME="local-cluster" envsubst < managed-cluster.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

CLUSTER_NAME="local-cluster" CLUSTER_TOKEN="$SUB1_TOKEN" CLUSTER_API="$CLUSTER_1_API" envsubst < auto-import-cluster-secret.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

CLUSTER_NAME="local-cluster" envsubst < klusterlet-config.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

# List Managed Cluster sets
oc --context "$CLUSTER_1_NAME" get managedclusters

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
