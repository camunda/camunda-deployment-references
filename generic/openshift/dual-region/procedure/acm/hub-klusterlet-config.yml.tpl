apiVersion: config.open-cluster-management.io/v1alpha1
kind: KlusterletConfig
metadata:
  name: hub-ca-config
spec:
  hubKubeAPIServerConfig:
    serverVerificationStrategy: UseAutoDetectedCABundle
    trustedCABundles:
    - name: hub-ca
      caBundle:
        name: hub-ca-bundle
        namespace: multicluster-engine
