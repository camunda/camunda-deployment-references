#!/bin/bash

# Import the first cluster
SUB1_TOKEN=$(oc --context "$CLUSTER_1_NAME" whoami -t)

# for the first cluster, the cluster name is hardcoded on purpose
CLUSTER_NAME="local-cluster" envsubst < managed-cluster.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

CLUSTER_NAME="local-cluster" CLUSTER_TOKEN="$SUB1_TOKEN" CLUSTER_API="$(rosa describe cluster --cluster "$CLUSTER_1_NAME" --output json | jq .api.url -r)" envsubst < auto-import-cluster-secret.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

CLUSTER_NAME="local-cluster" envsubst < klusterlet-config.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

# List Managed Cluster sets
oc --context "$CLUSTER_1_NAME" get managedclusters

# Import second cluster
SUB2_TOKEN=$(oc --context "$CLUSTER_2_NAME" whoami -t)

CLUSTER_NAME="$CLUSTER_2_NAME" envsubst < managed-cluster.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

CLUSTER_NAME="$CLUSTER_2_NAME" CLUSTER_TOKEN="$SUB2_TOKEN" CLUSTER_API="$(rosa describe cluster --cluster "$CLUSTER_2_NAME" --output json | jq .api.url -r)" envsubst < auto-import-cluster-secret.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

CLUSTER_NAME="$CLUSTER_2_NAME" envsubst < klusterlet-config.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

oc --context "$CLUSTER_1_NAME" get managedclusters --watch
# NAME            HUB ACCEPTED   MANAGED CLUSTER URLS                                 JOINED   AVAILABLE   AGE
# cl-oc-2         true           https://api.cl-oc-2.5egh.p3.openshiftapps.com:443    True     True        50s
# local-cluster   true           https://api.cl-oc-1.f70c.p3.openshiftapps.com:443   True     True        36m
