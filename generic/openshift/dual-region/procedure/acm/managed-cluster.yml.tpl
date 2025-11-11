apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: $CLUSTER_NAME
  labels:
    cloud: auto-detect
    vendor: auto-detect
    cluster.open-cluster-management.io/submariner-agent: "true"
    cluster.open-cluster-management.io/clusterset: oc-clusters
  annotations: {}
spec:
  hubAcceptsClient: true
