# Identity layer

`basic` (built-in users) or `oidc` (your provider). Produces one `oidc` object, or `null`, that the Camunda layer reads. An OIDC provider deployed on ECS by this architecture is parked: it would be a second producer of the same `oidc` object.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
