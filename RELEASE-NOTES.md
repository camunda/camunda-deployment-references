# Camunda Reference Architecture Release Notes

## 8.11 (unreleased)

Changes will appear here during the development cycle.

## 8.10

Changes since the 8.9 branch point (`206cf69c`), through `a824f23b`, plus the fixes backported to `stable/8.10` since.

### AWS ECS Fargate

- Added the dual-region reference with Aurora Global Database, Transit Gateway networking, and failover/failback procedures ([#2277](https://github.com/camunda/camunda-deployment-references/pull/2277)).
- Added Aurora MySQL as an alternative secondary storage engine for dual-region deployments ([#2914](https://github.com/camunda/camunda-deployment-references/pull/2914)).
- Changed dual-region failover/failback to use the zone management API ([#3482](https://github.com/camunda/camunda-deployment-references/pull/3482)).
- Added OIDC authentication, Management Identity, Keycloak, and Camunda Hub to the single-region reference ([#2917](https://github.com/camunda/camunda-deployment-references/pull/2917)).
- Added optional Prometheus monitoring, benchmark load generation, and AWS FIS chaos procedures ([#3457](https://github.com/camunda/camunda-deployment-references/pull/3457)).
- Added OpenSearch authentication to the dual-region Orchestration Cluster ([#3659](https://github.com/camunda/camunda-deployment-references/pull/3659)).
- Changed dual-region backups to use one shared S3 bucket ([#2832](https://github.com/camunda/camunda-deployment-references/pull/2832)).
- Dual-region failover now runs the Aurora planned switchover when the writer is in the failed region, and failover/failback wait until the switchover completes ([#3578](https://github.com/camunda/camunda-deployment-references/pull/3578)).

### AWS EKS

- Added the single-region Aurora PostgreSQL secondary storage variant ([#2724](https://github.com/camunda/camunda-deployment-references/pull/2724)).
- Added the experimental multi-region RDBMS reference with Aurora Global Database and Submariner service discovery ([#2940](https://github.com/camunda/camunda-deployment-references/pull/2940)).
- Multi-region bootstrap now declares only running zones. New regions join through the zone management API ([#3547](https://github.com/camunda/camunda-deployment-references/pull/3547)).
- Multi-region service exports now address the chart's per-zone Zeebe Services ([#3658](https://github.com/camunda/camunda-deployment-references/pull/3658), [#3662](https://github.com/camunda/camunda-deployment-references/pull/3662)).
- Replaced ingress-nginx with Project Contour in the single-region reference ([#2623](https://github.com/camunda/camunda-deployment-references/pull/2623)).
- Multi-region failover drains brokers and removes the lost zone ([#3546](https://github.com/camunda/camunda-deployment-references/pull/3546)). Failback validates the partition distribution before re-adding a zone ([#3483](https://github.com/camunda/camunda-deployment-references/pull/3483)).
- Multi-region failover and failback wait until the Aurora global switchover completes, and the procedures wait for the requested zone change ([#3578](https://github.com/camunda/camunda-deployment-references/pull/3578), [#3661](https://github.com/camunda/camunda-deployment-references/pull/3661)).
- Dual-region failback excludes Elasticsearch security feature state from snapshot restores to preserve credentials ([#3335](https://github.com/camunda/camunda-deployment-references/pull/3335)).

### AWS ROSA HCP and generic OpenShift

- Added a CloudNativePG secondary storage variant to the single-region ROSA reference ([#2724](https://github.com/camunda/camunda-deployment-references/pull/2724)).
- Added router TLS secret and HTTP/2 configuration procedures for gRPC access ([#2400](https://github.com/camunda/camunda-deployment-references/pull/2400)).
- Dual-region broker startup now waits for cross-region service DNS ([#2627](https://github.com/camunda/camunda-deployment-references/pull/2627)).

### Azure AKS

- Replaced ingress-nginx with Project Contour ([#2689](https://github.com/camunda/camunda-deployment-references/pull/2689)).
- Changed default node pools to Dsv6 and PostgreSQL Flexible Server compute to Dsv5 ([#2843](https://github.com/camunda/camunda-deployment-references/pull/2843), [#2848](https://github.com/camunda/camunda-deployment-references/pull/2848)).
- Added retries for transient PostgreSQL provisioning failures ([#3561](https://github.com/camunda/camunda-deployment-references/pull/3561)).

### AWS EC2 and Debian

- Installs Camunda 8.10 GA ([#3637](https://github.com/camunda/camunda-deployment-references/pull/3637)).
- Removed hardcoded demo credentials from service configuration templates ([#2423](https://github.com/camunda/camunda-deployment-references/pull/2423)).
- Added authenticated artifact downloads and fixed installation error handling ([#2397](https://github.com/camunda/camunda-deployment-references/pull/2397)).
- Migrated service configuration to unified `CAMUNDA_*` properties ([#3501](https://github.com/camunda/camunda-deployment-references/pull/3501)).

### Generic Kubernetes and local Kind

- Configured operator-managed PostgreSQL with two instances, required pod anti-affinity, and dedicated WAL volumes ([#3463](https://github.com/camunda/camunda-deployment-references/pull/3463)).
- Added a Keycloak readiness procedure to recover from transient OIDC discovery failures ([#2718](https://github.com/camunda/camunda-deployment-references/pull/2718)).

### Changed configuration and removed references

- Replaced standalone Console with Camunda Hub ([#2842](https://github.com/camunda/camunda-deployment-references/pull/2842)).
- Migrated Helm values to chart 15, including `global.host` and zone-aware `orchestration.partitioning` ([#2418](https://github.com/camunda/camunda-deployment-references/pull/2418), [#2424](https://github.com/camunda/camunda-deployment-references/pull/2424), [#3441](https://github.com/camunda/camunda-deployment-references/pull/3441)).
- Removed the Bitnami migration reference and its workflows. The 8.9 branch retains the migration tooling ([#2587](https://github.com/camunda/camunda-deployment-references/pull/2587)).
- Removed remaining ingress-nginx procedures and manifests after the Contour migration ([#3410](https://github.com/camunda/camunda-deployment-references/pull/3410)).
