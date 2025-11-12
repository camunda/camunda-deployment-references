apiVersion: v1
kind: Secret
metadata:
  name: auto-import-secret
  namespace: $CLUSTER_NAME
  annotations:
    managedcluster-import-controller.open-cluster-management.io/keeping-auto-import-secret: ""
stringData:
  autoImportRetry: "5"
  token: $CLUSTER_TOKEN
  server: $CLUSTER_API
type: Opaque
