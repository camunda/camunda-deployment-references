apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: $CLUSTER_NAME
  labels:
    cloud: auto-detect
    vendor: auto-detect
  annotations: {}
spec:
  hubAcceptsClient: true
