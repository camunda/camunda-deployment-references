prefix = "camunda-mgmt"

# The Orchestration Clusters that sign in against this provider. Each gets its own clients.
# base_url is the public URL of the cluster: use a hostname that you control, because the
# realm is imported when the provider starts for the first time.
clusters = {
  emea = { base_url = "https://emea.camunda.example.com" }
  apac = { base_url = "https://apac.camunda.example.com" }
}

enable_camunda_hub = true
