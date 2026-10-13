# Release notes

## 8.11 (unreleased)

Changes will appear here during the development cycle.

## 8.10

These notes cover merged changes from `206cf69c` to `a824f23b`, using the first-parent history.
The reference architectures are examples for learning and evaluation, not production-ready deployments.

### AWS ECS Fargate

* Added the experimental dual-region reference architecture with configurable networking, OpenSearch or Aurora PostgreSQL secondary storage, and cross-region DNS ([#2277](https://github.com/camunda/camunda-deployment-references/pull/2277)).
* Added Aurora MySQL as an alternative secondary-storage engine for dual-region deployments ([#2914](https://github.com/camunda/camunda-deployment-references/pull/2914)).
* Added Management Identity, Keycloak, Camunda Hub, and native OIDC authentication options to single-region deployments ([#2917](https://github.com/camunda/camunda-deployment-references/pull/2917)).
* Added an optional load-test overlay with Prometheus and Cloud Map discovery ([#3457](https://github.com/camunda/camunda-deployment-references/pull/3457)).
* Changed dual-region failover and failback to use the zone-aware Zones API ([#3482](https://github.com/camunda/camunda-deployment-references/pull/3482)).
* Fixed orchestration-cluster authentication to OpenSearch ([#3659](https://github.com/camunda/camunda-deployment-references/pull/3659)).
* Set the replication-lag budget alongside asynchronous replication ([#3438](https://github.com/camunda/camunda-deployment-references/pull/3438)).
* Changed dual-region backups to use one shared S3 bucket ([#2832](https://github.com/camunda/camunda-deployment-references/pull/2832)).
* Ordered service startup after EFS mount targets ([#3376](https://github.com/camunda/camunda-deployment-references/pull/3376)).

### AWS EKS

* Added the experimental multi-region RDBMS reference architecture with Aurora Global Database and Submariner ([#2940](https://github.com/camunda/camunda-deployment-references/pull/2940)).
* Added the single-region Aurora PostgreSQL secondary-storage variant ([#2724](https://github.com/camunda/camunda-deployment-references/pull/2724)).
* Replaced `ingress-nginx` with Project Contour in single-region and IRSA variants ([#2623](https://github.com/camunda/camunda-deployment-references/pull/2623)).
* Added a multi-region load-generator Job and macOS Bash compatibility ([#3403](https://github.com/camunda/camunda-deployment-references/pull/3403)).
* Changed multi-region initialization to declare running zones only. New zones join through the add-zone API ([#3547](https://github.com/camunda/camunda-deployment-references/pull/3547)).
* Added broker draining and lost-zone removal to failover ([#3546](https://github.com/camunda/camunda-deployment-references/pull/3546)).
* Checked partition distribution before zone re-addition ([#3483](https://github.com/camunda/camunda-deployment-references/pull/3483)).
* Fixed waits to follow the requested cluster change ([#3661](https://github.com/camunda/camunda-deployment-references/pull/3661)).
* Detached readers from a switched Aurora writer before teardown ([#3628](https://github.com/camunda/camunda-deployment-references/pull/3628)).
* Adjusted replication-lag handling and made lag-based pausing optional ([#3440](https://github.com/camunda/camunda-deployment-references/pull/3440), [#3449](https://github.com/camunda/camunda-deployment-references/pull/3449)).
* Migrated dual-region values from `global.multiregion` to `orchestration.partitioning` ([#3441](https://github.com/camunda/camunda-deployment-references/pull/3441)).
* Fixed Elasticsearch credential synchronization during dual-region failback ([#3335](https://github.com/camunda/camunda-deployment-references/pull/3335), [#3346](https://github.com/camunda/camunda-deployment-references/pull/3346), [#3489](https://github.com/camunda/camunda-deployment-references/pull/3489)).
* Updated dual-region multi-tenancy values ([#3274](https://github.com/camunda/camunda-deployment-references/pull/3274), [#3565](https://github.com/camunda/camunda-deployment-references/pull/3565)).
* Fixed per-zone service addressing and zone-list bounds ([#3658](https://github.com/camunda/camunda-deployment-references/pull/3658), [#3662](https://github.com/camunda/camunda-deployment-references/pull/3662)).
* Fixed the Camunda Hub disable key and retried management API tunnels ([#3615](https://github.com/camunda/camunda-deployment-references/pull/3615)).

### AWS OpenShift ROSA HCP

* Added a single-region RDBMS variant with CloudNativePG ([#2724](https://github.com/camunda/camunda-deployment-references/pull/2724)).
* Replaced Terraform file rewrites with configuration overrides ([#2982](https://github.com/camunda/camunda-deployment-references/pull/2982)).
* Added retries for transient compute-node timeouts ([#2588](https://github.com/camunda/camunda-deployment-references/pull/2588)).
* Hardened cleanup after failed destroy operations and ghost-cluster cleanup ([#3136](https://github.com/camunda/camunda-deployment-references/pull/3136), [#3176](https://github.com/camunda/camunda-deployment-references/pull/3176), [#3177](https://github.com/camunda/camunda-deployment-references/pull/3177), [#3276](https://github.com/camunda/camunda-deployment-references/pull/3276)).
* Added Submariner gateway diagnostics, installer-role inventory, and EBS CSI failure evidence ([#2700](https://github.com/camunda/camunda-deployment-references/pull/2700), [#3283](https://github.com/camunda/camunda-deployment-references/pull/3283), [#3560](https://github.com/camunda/camunda-deployment-references/pull/3560), [#3559](https://github.com/camunda/camunda-deployment-references/pull/3559)).

### Azure AKS

* Replaced `ingress-nginx` with Project Contour in single-region and RDBMS variants ([#2689](https://github.com/camunda/camunda-deployment-references/pull/2689)).
* Changed node pools to `Standard_D*s_v6` SKUs and PostgreSQL Flexible Server compute to Ddsv5 ([#2843](https://github.com/camunda/camunda-deployment-references/pull/2843), [#2848](https://github.com/camunda/camunda-deployment-references/pull/2848)).
* Retried transient PostgreSQL creation failures ([#3561](https://github.com/camunda/camunda-deployment-references/pull/3561)).
* Added Azure Activity Log capture on cluster-creation failure ([#3380](https://github.com/camunda/camunda-deployment-references/pull/3380)).

### AWS EC2 and Debian

* Changed EC2 installation from SNAPSHOT to Camunda 8.10 GA ([#3637](https://github.com/camunda/camunda-deployment-references/pull/3637)).
* Replaced legacy `zeebe.*` configuration keys ([#3501](https://github.com/camunda/camunda-deployment-references/pull/3501)).
* Added distribution and Connectors download caching for EC2 tests ([#2657](https://github.com/camunda/camunda-deployment-references/pull/2657)).
* Removed hardcoded demo credentials from EC2 procedures ([#2423](https://github.com/camunda/camunda-deployment-references/pull/2423)).
* Vendored the Debian Connectors launcher to avoid Spring Boot runtime JAR mismatches ([#2505](https://github.com/camunda/camunda-deployment-references/pull/2505)).

### Generic Kubernetes, OpenShift, and local Kind

* Changed CloudNativePG deployments to two instances with dedicated WAL volumes ([#3463](https://github.com/camunda/camunda-deployment-references/pull/3463)).
* Added an OIDC startup helper that waits for Keycloak ([#2718](https://github.com/camunda/camunda-deployment-references/pull/2718)).
* Added source chart builds without private OCI registry authentication ([#2823](https://github.com/camunda/camunda-deployment-references/pull/2823), [#2827](https://github.com/camunda/camunda-deployment-references/pull/2827), [#2841](https://github.com/camunda/camunda-deployment-references/pull/2841), [#2858](https://github.com/camunda/camunda-deployment-references/pull/2858)).
* Fixed the Identity database username key for chart 15 ([#3512](https://github.com/camunda/camunda-deployment-references/pull/3512)).
* Fixed OpenShift detection to inspect API groups ([#3476](https://github.com/camunda/camunda-deployment-references/pull/3476)).
* Removed a no-op Keycloak flag and obsolete ingress annotations ([#3522](https://github.com/camunda/camunda-deployment-references/pull/3522), [#3410](https://github.com/camunda/camunda-deployment-references/pull/3410), [#3415](https://github.com/camunda/camunda-deployment-references/pull/3415)).

### Shared platform and resilience

* Removed standalone Console and migrated to Camunda Hub ([#2842](https://github.com/camunda/camunda-deployment-references/pull/2842)).
* Migrated chart values to `camundaHub` and `extraConfiguration` ([#2400](https://github.com/camunda/camunda-deployment-references/pull/2400), [#3399](https://github.com/camunda/camunda-deployment-references/pull/3399), [#2418](https://github.com/camunda/camunda-deployment-references/pull/2418), [#2424](https://github.com/camunda/camunda-deployment-references/pull/2424), [#2812](https://github.com/camunda/camunda-deployment-references/pull/2812), [#2871](https://github.com/camunda/camunda-deployment-references/pull/2871)).
* Added AWS FIS experiment cleanup through the FIS-Admin role ([#3624](https://github.com/camunda/camunda-deployment-references/pull/3624)).
* Removed demo credentials from test suites and added guards against default credentials ([#2523](https://github.com/camunda/camunda-deployment-references/pull/2523), [#2526](https://github.com/camunda/camunda-deployment-references/pull/2526), [#2574](https://github.com/camunda/camunda-deployment-references/pull/2574), [#2694](https://github.com/camunda/camunda-deployment-references/pull/2694)).
* Hardened gRPC timeouts, reachability probes, and partition-readiness checks ([#2721](https://github.com/camunda/camunda-deployment-references/pull/2721), [#2770](https://github.com/camunda/camunda-deployment-references/pull/2770), [#2778](https://github.com/camunda/camunda-deployment-references/pull/2778), [#2784](https://github.com/camunda/camunda-deployment-references/pull/2784)).
