# Secondary storage layer

Aurora PostgreSQL for the Orchestration Cluster's RDBMS secondary storage, the database admin secret and a one-time seed task that creates the IAM-authenticated database users.

To turn the cluster into an Aurora Global Database later, see the evolution runbook: Global Databases do not support `db.t3`/`db.t4g`, so start from an r-class `db_instance_class` if you plan to grow.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
