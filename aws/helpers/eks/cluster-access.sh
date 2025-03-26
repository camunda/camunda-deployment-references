#!/bin/bash

export CLUSTER_NAME="$(terraform console <<<local.eks_cluster_name | jq -r)"

aws eks --region "$AWS_REGION" update-kubeconfig --name "$CLUSTER_NAME" --alias "$CLUSTER_NAME"
