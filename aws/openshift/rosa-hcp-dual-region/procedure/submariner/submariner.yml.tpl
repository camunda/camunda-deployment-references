apiVersion: addon.open-cluster-management.io/v1alpha1
kind: ManagedClusterAddOn
metadata:
  name: submariner
  namespace: $CLUSTER_2_NAME
spec:
  installNamespace: submariner-operator
---
apiVersion: submarineraddon.open-cluster-management.io/v1alpha1
kind: SubmarinerConfig
metadata:
  name: submariner
  namespace: $CLUSTER_2_NAME
spec:
  gatewayConfig: {}
  IPSecNATTPort: 4500
  airGappedDeployment: true
  NATTEnable: true
  cableDriver: libreswan
  globalCIDR: ""
  loadBalancerEnable: true
---
apiVersion: addon.open-cluster-management.io/v1alpha1
kind: ManagedClusterAddOn
metadata:
  name: submariner
  namespace: local-cluster
spec:
  installNamespace: submariner-operator
---
apiVersion: submarineraddon.open-cluster-management.io/v1alpha1
kind: SubmarinerConfig
metadata:
  name: submariner
  namespace: local-cluster
spec:
  gatewayConfig: {}
  IPSecNATTPort: 4500
  airGappedDeployment: true
  NATTEnable: true
  cableDriver: libreswan
  globalCIDR: ""
  loadBalancerEnable: true
---
apiVersion: submariner.io/v1alpha1
kind: Broker
metadata:
  name: submariner-broker
  namespace: oc-clusters-broker
  labels:
    cluster.open-cluster-management.io/backup: submariner
spec:
  globalnetEnabled: false
  globalnetCIDRRange: ""
