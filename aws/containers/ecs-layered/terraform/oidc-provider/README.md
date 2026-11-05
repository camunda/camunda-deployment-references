# OIDC provider layer

An OIDC provider on ECS for the management plane. It imports a realm on first start with one orchestration and one connectors client for each Orchestration Cluster in `clusters`, the Management Identity client, and the Camunda Hub client. Its `clusters` output is the `external_oidc` object of the identity layer of each cluster, and its `management` output is what Management Identity and Camunda Hub read.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
