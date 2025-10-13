apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: $CLUSTER_NAME
  labels:
    name: $CLUSTER_NAME
    cluster.open-cluster-management.io/clusterset: oc-clusters
  annotations:
    agent.open-cluster-management.io/klusterlet-config: hub-ca-config
spec:
  hubAcceptsClient: true
