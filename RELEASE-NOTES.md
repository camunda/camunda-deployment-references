# Camunda Reference Architecture Release Notes

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
- The ECS and EKS Aurora switchover helpers fail at once when a second switchover cancels the pending one, instead of waiting 900 seconds. They return `2` and ask for a rerun when a switchover is still running at the timeout ([#3681](https://github.com/camunda/camunda-deployment-references/pull/3681), backport [#3682](https://github.com/camunda/camunda-deployment-references/pull/3682)).
- ECS and EKS `failback.sh` report the AWS error when `describe-global-clusters` fails. Before, it read the error as an empty topology ([#3681](https://github.com/camunda/camunda-deployment-references/pull/3681), backport [#3682](https://github.com/camunda/camunda-deployment-references/pull/3682)).
- Dual-region `failover.sh` and `failback.sh` wait until every partition has exactly one leader before reporting success, and report an unreachable gateway separately from an unsettled cluster. Before, a single read right after the Aurora switchover could fail a failover that had succeeded, and `failback.sh` aborted after completing ([#3595](https://github.com/camunda/camunda-deployment-references/pull/3595), backport [#3755](https://github.com/camunda/camunda-deployment-references/pull/3755)).
- Dual-region `verify_dual_region.sh` fails when the health-check process is not deployed. Deploy it once with the new `deploy_health_check_process.sh`, step 6 of the README quick start. With `--failed-region`, it checks replication factor 2 and one leader per partition instead of the broker count ([#3595](https://github.com/camunda/camunda-deployment-references/pull/3595), backport [#3755](https://github.com/camunda/camunda-deployment-references/pull/3755)).
- Added the dual-region `db_force_destroy` input (default `true`), so `terraform destroy` can remove the Aurora Global cluster after a failover. It controls member detachment only; it is not deletion protection ([#3595](https://github.com/camunda/camunda-deployment-references/pull/3595), backport [#3755](https://github.com/camunda/camunda-deployment-references/pull/3755)).
- Uses Camunda 8.10.5, which fixes a dual-region forced zone removal that never completed when a broker had seen no peer ([#3765](https://github.com/camunda/camunda-deployment-references/pull/3765)).
- ECS `failback.sh` empties the recovered zone's EFS primary storage before it scales the brokers back up, so they do not rejoin with stale Raft state. It refuses to run while the service is not scaled to 0 ([#3767](https://github.com/camunda/camunda-deployment-references/pull/3767), backport [#3874](https://github.com/camunda/camunda-deployment-references/pull/3874)).

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
- The `rhcs` provider constraint skips version 1.7.11, which was published without its provider binary. `terraform init` failed with `provider binary not found` ([#3818](https://github.com/camunda/camunda-deployment-references/pull/3818), backport [#3819](https://github.com/camunda/camunda-deployment-references/pull/3819)).

### Azure AKS

- Replaced ingress-nginx with Project Contour ([#2689](https://github.com/camunda/camunda-deployment-references/pull/2689)).
- Changed default node pools to Dsv6 and PostgreSQL Flexible Server compute to Dsv5 ([#2843](https://github.com/camunda/camunda-deployment-references/pull/2843), [#2848](https://github.com/camunda/camunda-deployment-references/pull/2848)).
- Added retries for transient PostgreSQL provisioning failures ([#3561](https://github.com/camunda/camunda-deployment-references/pull/3561)).

### AWS EC2 and Debian

- Installs Camunda 8.10 GA ([#3637](https://github.com/camunda/camunda-deployment-references/pull/3637)).
- Installs Camunda 8.10.5 ([#3765](https://github.com/camunda/camunda-deployment-references/pull/3765)).
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
