We will document the installation of the Camunda Helm chart with operators for the infrastructure components.
These are my installation notes.

We assume that you have a Kubernetes cluster where you have generic rights on a namespace for Camunda and the right to create other namespaces for the operators of the infrastructure components, as well as the rights to install operators and CRDs. The operators also need to create ClusterRoles. It is recommended to check the prerequisites for each operator as needed or adjust your user’s permissions on the cluster used in case of insufficient permissions.

Please note that all operators installation requires ClusterAdmin privileges or variant depending of the roles permissions your kubernetes cluster is configured with.

<!-- TODO: add a link that explains what an operator is -->

First, make sure a namespace is available; in the following we will use the camunda namespace:
kubectl create namespace camunda

Select the camunda namespace:
kubectl config set-context --current --namespace=camunda

Our installation begins by enumerating the required infrastructure components:
- elasticsearch: to store Zeebe and Camunda data (hereafter referred to as the orchestration cluster)
- postgresql: for Keycloak, Camunda Identity, and optionally Web Modeler if you install it. In this exercise we will deploy one Postgres instance for Identity, one for Keycloak, and one for Web Modeler.
- keycloak for the authentication part of Camunda Identity

We will do it in minimal dependency order: Elasticsearch, Postgres, then Keycloak

## Installing the PostgreSQL Operator

To install PostgreSQL on Kubernetes, we chose CloudNativePG which is a CNCF component (https://landscape.cncf.io/?item=app-definition-and-development--database--cloudnativepg) under the APACHE 2.0 license (https://github.com/cloudnative-pg/cloudnative-pg?tab=readme-ov-file)

To learn the prerequisites for this installation, refer to the project documentation: https://cloudnative-pg.io/documentation/current/supported_releases/. This operator works on Kubernetes and OpenShift.

You will need a dedicated namespace for the operator controller: `cnpg-system`

Regarding the target PostgreSQL version, we take the common denominator for the current version of Camunda: https://docs.camunda.io/docs/next/reference/supported-environments/#component-requirements, i.e. Postgres 15

### Quickstart

This is an excerpt from https://cloudnative-pg.io/documentation/current/quickstart/#part-2-install-cloudnativepg

#### Install the Operator
<!-- TODO: renovate -->
We start by installing the latest operator manifest (https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml)

```bash
kubectl create namespace cnpg -system

kubectl apply -n cnpg-system --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml
```

Then verify the installation status:

```bash
kubectl rollout status deployment \
  -n cnpg-system cnpg-controller-manager
```

You will notice that the controller deployment succeeded in the cpng-system namespace. Using a dedicated namespace for the controller is standard practice for operators on Kubernetes.

If you want to integrate the deployment of this operator alongside the Camunda chart, we recommend using: https://github.com/cloudnative-pg/charts

#### Instanciate PostgreSQL clusters

We will spawn 3 PostgreSQL clusters, one for Keycloak, one for Camunda Identity, and one for Webmodeler.
```yaml
kind: Cluster
metadata:
  name: pg-identity
spec:
  instances: 1
  description: "PostgreSQL cluster for Camunda Identity"
  storage:
    size: 15Gi
  superuserSecret:
    name: pg-identity-superuser-secret
  bootstrap:
    initdb:
      database: identity
      owner: identity
      dataChecksums: true
      secret:
        name: pg-identity-secret
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-keycloak
spec:
  instances: 1
  description: "PostgreSQL cluster for Keycloak"
  storage:
    size: 15Gi
  superuserSecret:
    name: pg-keycloak-superuser-secret
  bootstrap:
    initdb:
      database: keycloak
      owner: keycloak
      dataChecksums: true
      secret:
        name: pg-keycloak-secret
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-webmodeler
spec:
  instances: 1
  description: "PostgreSQL cluster for Webmodeler"
  superuserSecret:
    name: pg-webmodeler-superuser-secret
  bootstrap:
    initdb:
      database: webmodeler
      owner: webmodeler
      secret:
        name: pg-webmodeler-secret
  storage:
    size: 15Gi
```

Create the basic auth secrets with random passwords (openssl). Run these commands in the camunda namespace.

```bash
# Identity superuser (username=root) and bootstrap (username=identity)
IDENTITY_SUPER_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-identity-superuser-secret -n camunda \
  --from-literal=username=root \
  --from-literal=password="$IDENTITY_SUPER_PASS"

IDENTITY_BOOT_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-identity-secret -n camunda \
  --from-literal=username=identity \
  --from-literal=password="$IDENTITY_BOOT_PASS"

# Keycloak superuser (username=root) and bootstrap (username=keycloak)
KEYCLOAK_SUPER_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-keycloak-superuser-secret -n camunda \
  --from-literal=username=root \
  --from-literal=password="$KEYCLOAK_SUPER_PASS"

KEYCLOAK_BOOT_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-keycloak-secret -n camunda \
  --from-literal=username=keycloak \
  --from-literal=password="$KEYCLOAK_BOOT_PASS"

# Webmodeler superuser (username=root) and bootstrap (username=webmodeler)
WEBM_SUPER_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-webmodeler-superuser-secret -n camunda \
  --from-literal=username=root \
  --from-literal=password="$WEBM_SUPER_PASS"

WEBM_BOOT_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-webmodeler-secret -n camunda \
  --from-literal=username=webmodeler \
  --from-literal=password="$WEBM_BOOT_PASS"
```
bash
Quick check (example for pg-identity-superuser-secret):

```bash
kubectl get secret pg-identity-superuser-secret -n camunda -o yaml | base64 --decode ; echo
kubectl get secret pg-identity-superuser-secret -n camunda -o jsonpath='{.data.username}' | base64 --decode ; echo
kubectl get secret pg-identity-superuser-secret -n camunda -o jsonpath='{.data.password}' | base64 --decode ; echo
```
```

Save the above manifest to a file named `pg-clusters.yml` and apply it in the `camunda` namespace with:

```bash
kubectl apply -n camunda -f pg-clusters.yml
```
Verify that the clusters have been created (wait a few seconds for them to become healthy):

```bash
# Wait up to 5 minutes (300s), polling every 5s, then display the final state
echo "Waiting for clusters (max 5m) to become 'healthy'..."
timeout=300
interval=5
end=$((SECONDS+timeout))

while [ $SECONDS -lt $end ]; do
  count=$(kubectl get clusters -n camunda 2>/dev/null | grep -E '^pg-(identity|keycloak|webmodeler)\b' | grep -c 'Cluster in healthy state' || true)
  if [ "$count" -eq 3 ]; then
    echo "All clusters are in 'healthy' state."
    break
  fi
  sleep $interval
done

kubectl get clusters -n camunda
```

Example expected output:

```
NAME            AGE   INSTANCES   READY   STATUS                     PRIMARY
pg-identity     61s   1           1       Cluster in healthy state   pg-identity-1
pg-keycloak     61s   1           1       Cluster in healthy state   pg-keycloak-1
pg-webmodeler   60s   1           1       Cluster in healthy state   pg-webmodeler-1
```

Access to the PostgreSQL clusters is via Kubernetes Services:

```
kubectl -n camunda get svc | grep "pg-"

# expected result
NAME               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
pg-identity-r      ClusterIP   10.190.176.124   <none>        5432/TCP   3m56s
pg-identity-ro     ClusterIP   10.190.157.2     <none>        5432/TCP   3m56s
pg-identity-rw     ClusterIP   10.190.45.41     <none>        5432/TCP   3m56s
pg-keycloak-r      ClusterIP   10.190.233.51    <none>        5432/TCP   3m56s
pg-keycloak-ro     ClusterIP   10.190.180.245   <none>        5432/TCP   3m56s
pg-keycloak-rw     ClusterIP   10.190.216.140   <none>        5432/TCP   3m56s
pg-webmodeler-r    ClusterIP   10.190.1.7       <none>        5432/TCP   3m55s
pg-webmodeler-ro   ClusterIP   10.190.151.51    <none>        5432/TCP   3m55s
pg-webmodeler-rw   ClusterIP   10.190.148.70    <none>        5432/TCP   3m55s
```

The credentials to access the databases are stored in Kubernetes secrets that you previously created.

All configuration options for the PostgreSQL cluster are available in the official CloudNativePG documentation (https://cloudnative-pg.io/documentation/current/cloudnative-pg.v1/)

For monitoring, follow https://cloudnative-pg.io/documentation/current/quickstart/#part-4-monitor-clusters-with-promet

The PostgreSQL cluster installation is now complete; configuration in the chart will be covered in the Camunda installation chapter.

## Installing the Elasticsearch Operator

To install Elasticsearch on Kubernetes, we chose ECK (Elastic Cloud on Kubernetes), which is the official operator provided by Elastic under the Elastic license (https://www.elastic.co/licensing/elastic-license).

To learn the prerequisites for this installation, refer to the official documentation https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/deploy-an-orchestrator. This operator works on Kubernetes and OpenShift (https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s#k8s-supported).

You will need a dedicated namespace for the operator controller: `elastic-system`

Regarding the target version of Elasticsearch, we take the common denominator for the current version of Camunda: https://docs.camunda.io/docs/next/reference/supported-environments/#component-requirements, i.e. Elasticsearch 8.16+

### Quickstart

This is an excerpt from https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install-using-yaml-manifest-quickstart

#### Install the Operator

<!-- TODO: renovate -->

We start by installing the latest operator manifest (https://download.elastic.co/downloads/eck/3.1.0/operator.yaml) as well as its CRDs (https://download.elastic.co/downloads/eck/3.1.0/crds.yaml)

```bash
kubectl apply --server-side -f \
  https://download.elastic.co/downloads/eck/3.1.0/crds.yaml

sleep 10

kubectl create namespace elastic-system

kubectl apply -n elastic-system --server-side -f \
  https://download.elastic.co/downloads/eck/3.1.0/operator.yaml
```

You should see the CRD creation:

```text
customresourcedefinition.apiextensions.k8s.io/agents.agent.k8s.elastic.co created
customresourcedefinition.apiextensions.k8s.io/apmservers.apm.k8s.elastic.co created
customresourcedefinition.apiextensions.k8s.io/beats.beat.k8s.elastic.co created
customresourcedefinition.apiextensions.k8s.io/elasticmapsservers.maps.k8s.elastic.co created
customresourcedefinition.apiextensions.k8s.io/elasticsearches.elasticsearch.k8s.elastic.co created
customresourcedefinition.apiextensions.k8s.io/kibanas.kibana.k8s.elastic.co created
customresourcedefinition.apiextensions.k8s.io/logstashes.logstash.k8s.elastic.co created
```

followed by the operator creation:

```text
namespace/elastic-system serverside-applied
serviceaccount/elastic-operator serverside-applied
secret/elastic-webhook-server-cert serverside-applied
configmap/elastic-operator serverside-applied
clusterrole.rbac.authorization.k8s.io/elastic-operator serverside-applied
clusterrole.rbac.authorization.k8s.io/elastic-operator-view serverside-applied
clusterrole.rbac.authorization.k8s.io/elastic-operator-edit serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/elastic-operator serverside-applied
service/elastic-webhook-server serverside-applied
statefulset.apps/elastic-operator serverside-applied
validatingwebhookconfiguration.admissionregistration.k8s.io/elastic-webhook.k8s.elastic.co serverside-applied
```

Then verify the installation status:

```bash
kubectl get pod \
  -n elastic-system elastic-operator
```

The pod should be ready and running:

```text
NAME                 READY   STATUS    RESTARTS   AGE
elastic-operator-0   1/1     Running   0          1m
```

You will notice that the controller deployment succeeded in the elastic-system namespace. Using a dedicated namespace for the controller is standard practice for operators on Kubernetes.

If you want to integrate the deployment of this operator alongside the Camunda chart, we recommend using: https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install-using-helm-chart

#### Instantiate an Elasticsearch cluster

This manifest instantiates an Elasticsearch (ECK) 8.18.0 highly available cluster with 3 master nodes, persistent storage, and bounded resources.

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
spec:
  version: 8.18.0
  nodeSets:
  - name: masters
    count: 3
    config:
      node.store.allow_mmap: false
      # Disable deprecation warnings - https://github.com/camunda/camunda/issues/26285
      logger.org.elasticsearch.deprecation: "OFF"
      node.roles: ["master"]
    podTemplate:
      spec:
        affinity:
          podAntiAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              - labelSelector:
                  matchExpressions:
                    - key: elasticsearch.k8s.elastic.co/cluster-name
                      operator: In
                      values:
                        - elasticsearch
                topologyKey: "kubernetes.io/hostname"
        containers:
        - name: elasticsearch
          securityContext:
            readOnlyRootFilesystem: true
          env:
            - name: ELASTICSEARCH_ENABLE_REST_TLS
              value: "false"
          resources:
            requests:
              cpu: 1
              memory: 2Gi
            limits:
              cpu: 2
              memory: 2Gi
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: 64Gi
```

All configuration options for the Elasticsearch cluster are available in the official ECK documentation (hhttps://www.elastic.co/guide/en/cloud-on-k8s/1.0/k8s-elasticsearch-k8s-elastic-co-v1.html)

Save this manifest as `elasticsearch.yaml` and apply it in the "camunda" namespace to deploy the cluster required by the orchestration cluster:

```bash
kubectl apply -n camunda -f elasticsearch.yaml

# Wait up to 10 minutes for health=green and phase=Ready
echo "Waiting for Elasticsearch cluster (max 10m) to reach health=green..."
ns=camunda
name=elasticsearch
timeout=600
interval=10
end=$((SECONDS+timeout))

while [ $SECONDS -lt $end ]; do
  health=$(kubectl get elasticsearch "$name" -n "$ns" -o jsonpath='{.status.health}' 2>/dev/null || true)
  phase=$(kubectl get elasticsearch "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)

  if [ "$health" = "green" ] && [ "$phase" = "Ready" ]; then
    echo "Elasticsearch cluster is ready (health=$health, phase=$phase)."
    break
  fi

  printf "health=%s phase=%s ...\n" "${health:-unknown}" "${phase:-unknown}"
  sleep $interval
done

if [ $SECONDS -ge $end ]; then
  echo "Timeout reached. Current cluster state:"
fi

kubectl get elasticsearch "$name" -n "$ns" -o wide || true
kubectl get pods -n "$ns" -l elasticsearch.k8s.elastic.co/cluster-name="$name" || true
```

```bash
kubectl get elasticsearch -n camunda
```

Example expected output:

```text
NAME            HEALTH   NODES   VERSION   PHASE   AGE
elasticsearch   green    3       8.18.0    Ready   9m21s
```

Access to the Elasticsearch clusters is via Kubernetes Services:

```bash
kubectl -n camunda get svc | grep "elasticsearch"
```

expected result:
```text
NAME               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
elasticsearch-es-http            ClusterIP   10.190.85.172    <none>        9200/TCP   9m49s
elasticsearch-es-internal-http   ClusterIP   10.190.111.249   <none>        9200/TCP   9m49s
elasticsearch-es-masters         ClusterIP   None             <none>        9200/TCP   9m48s
elasticsearch-es-transport       ClusterIP   None             <none>        9300/TCP   9m49s
```

The credentials for accessing the Elasticsearch cluster are stored in Kubernetes secrets created by the operator; the default user is `elastic`

```bash
kubectl get secret elasticsearch-es-elastic-user -n camunda -o yaml
```

For continuation, we invite you to continue reading the official installation guide: https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/configure-deployments

The Elastic cluster installation is now complete; configuration in the chart will be covered in the Camunda installation chapter.

## Installing the Keycloak Operator

To install Keycloak on Kubernetes, we chose the Keycloak Operator which is a CNCF component (https://landscape.cncf.io/?item=provisioning--security-compliance--keycloak) under the APACHE 2.0 license (https://github.com/cloudnative-pg/cloudnative-pg?tab=readme-ov-file)

To learn the prerequisites for this installation, see the official Keycloak Operator documentation: https://www.keycloak.org/guides#operator. This operator works on Kubernetes and OpenShift.

It is recommended to use a dedicated namespace for the operator controller: keycloak-system (or install it in the same namespace as your instances if you limit its scope).

Regarding the target Keycloak version, we take the common denominator for the current version of Camunda: https://docs.camunda.io/docs/next/reference/supported-environments/#component-requirements, i.e. Keycloak 26+.

### Quickstart

This is an excerpt from https://www.keycloak.org/operator/installation#_installing_by_using_kubectl_without_operator_lifecycle_manager

#### Install the Operator

<!-- TODO: renovate -->

We start by installing the latest operator manifest as well as its CRDs:

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml

kubectl apply --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml

sleep 10

kubectl apply -n camunda --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/kubernetes.yml
```

You should see the CRD creation:

```text
customresourcedefinition.apiextensions.k8s.io/keycloaks.k8s.keycloak.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/keycloakrealmimports.k8s.keycloak.org serverside-applied
```

followed by the operator creation:

```text
serviceaccount/keycloak-operator serverside-applied
clusterrole.rbac.authorization.k8s.io/keycloak-operator-clusterrole serverside-applied
clusterrole.rbac.authorization.k8s.io/keycloakrealmimportcontroller-cluster-role serverside-applied
clusterrole.rbac.authorization.k8s.io/keycloakcontroller-cluster-role serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/keycloak-operator-clusterrole-binding serverside-applied
role.rbac.authorization.k8s.io/keycloak-operator-role serverside-applied
rolebinding.rbac.authorization.k8s.io/keycloak-operator-role-binding serverside-applied
rolebinding.rbac.authorization.k8s.io/keycloakrealmimportcontroller-role-binding serverside-applied
rolebinding.rbac.authorization.k8s.io/keycloakcontroller-role-binding serverside-applied
rolebinding.rbac.authorization.k8s.io/keycloak-operator-view serverside-applied
service/keycloak-operator serverside-applied
deployment.apps/keycloak-operator serverside-applied
```

Then verify the installation status:

```bash
kubectl rollout status deployment \
  -n camunda keycloak-operator
```

You will notice that the controller deployment succeeded in the camunda namespace, the operator watch the namespace where it is installed.

As time of now, no helm chart is planned to be integrated by the keycloak team https://github.com/keycloak/keycloak/issues/16210#issuecomment-1462203645.


#### Instantiate a Keycloak instance

This manifest instantiates a Keycloak instance with the following configuration:

- Database configuration from the previous section CNPG consuming secrets from `keycloak-db`

```yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: keycloak
spec:
  instances: 1
  db:
    host: pg-keycloak-rw # this service is provided by the CNPG keycloak
    port: 5432
    database: keycloak
    schema: public
    usernameSecret:
      name: pg-keycloak-secret
      key: username
    passwordSecret:
      name: pg-keycloak-secret
      key: password
  http:
    httpEnabled: true
  transaction:
    xaEnabled: false
  additionalOptions:
    - name: http-enabled
      value: "true"
  hostname:
    hostname: localhost
  #  hostname: keycloak.example.com
  #  tlsSecret: example-tls
  #  backchannelDynamic: true
    strict: false
  resources:
    limits:
      cpu: 500m
      memory: 1Gi
    requests:
      cpu: 250m
      memory: 512Mi
```

All configuration options for the Keycloak cluster are available in the official documentation (https://www.keycloak.org/operator/advanced-configuration).

<!-- TODO: document usage with a real domain exposed (tls + change hostname )-->


Save the manifest as keycloak.yml and deploy it in the camunda namespace:

```bash
kubectl apply -n camunda -f keycloak.yml
```

Then monitor the installation of keycloak
```bash
# Wait up to 5 minutes for the Keycloak CR to become Ready
echo "Waiting for Keycloak (max 5m) to become Ready..."
ns=camunda
name=keycloak
timeout=300
interval=5
end=$((SECONDS+timeout))

while [ $SECONDS -lt $end ]; do
  ready=$(kubectl get keycloak "$name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [ "$ready" = "True" ]; then
    echo "Keycloak is Ready."
    break
  fi
  printf "Ready=%s ...\n" "${ready:-unknown}"
  sleep $interval
done

kubectl get keycloak "$name" -n "$ns" -o wide || true
kubectl get pods -n "$ns" -l app.kubernetes.io/name=keycloak,app.kubernetes.io/instance="$name" || true
kubectl get svc -n "$ns" | grep keycloak || true
```

Fetch the initial admin credentials (operator-generated secret: keycloak-initial-admin):

```bash
kubectl -n camunda get secret keycloak-initial-admin -o jsonpath='{.data.username}' | base64 --decode ; echo
kubectl -n camunda get secret keycloak-initial-admin -o jsonpath='{.data.password}' | base64 --decode ; echo
```

Access the admin console:
- Without Ingress/hostname:
  - Port-forward locally, then open http://localhost:8080/admin/
  ```bash
  kubectl -n camunda port-forward svc/keycloak 8080:8080
  ```
- With hostname and TLS configured (spec.hostname + spec.http.tlsSecret):
  - Open https://<your-hostname>/admin/

Best practice: change the admin password after the first login.

#### Configure a Realm for Camunda

<!-- TODO: Realm CR -->

1. Log in to the Keycloak admin console.
2. Create a new realm for Camunda.
3. Configure the realm settings as needed.

## Install Camunda

<!-- TODO: handle images used by the operators (SBOM) -->
