prefix = "camunda-mgmt"

# One Camunda Hub for every cluster. Take each entry from the cluster_registration output of
# the Camunda layer of that cluster.
clusters = {
  emea = {
    version       = "8.10.0"
    rest_url      = "http://orchestration-cluster.camunda-emea-oc.service.local:8080"
    grpc_url      = "grpc://orchestration-cluster.camunda-emea-oc.service.local:26500"
    readiness_url = "http://orchestration-cluster.camunda-emea-oc.service.local:9600/actuator/health/readiness"
  }
  apac = {
    name          = "Asia Pacific"
    version       = "8.10.0"
    rest_url      = "http://orchestration-cluster.camunda-apac-oc.service.local:8080"
    grpc_url      = "grpc://orchestration-cluster.camunda-apac-oc.service.local:26500"
    readiness_url = "http://orchestration-cluster.camunda-apac-oc.service.local:9600/actuator/health/readiness"
  }
}
