#!/bin/bash

envsubst < submariner.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -
