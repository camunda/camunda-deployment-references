#!/bin/bash

envsubst < submariner.yml.tpl | oc --context "$CLUSTER_0" apply -f -
