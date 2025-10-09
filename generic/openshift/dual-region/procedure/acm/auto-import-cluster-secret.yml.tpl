apiVersion: v1
kind: Secret
metadata:
  name: auto-import-secret
  namespace: $CLUSTER_NAME
stringData:
  autoImportRetry: "5"
  token: $CLUSTER_TOKEN
  server: $CLUSTER_API
  ca.crt: |
${CLUSTER_CA_CERT}
type: Opaque
