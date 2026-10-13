# Camunda Reference Architecture Release Notes

## 8.10

Changes since the 8.9 branch point (`206cf69c`), through `a824f23b`.

### AWS ECS Fargate

- Added the dual-region reference with Aurora Global Database, Transit Gateway networking, and failover/failback procedures (#2277).
- Added Aurora MySQL as an alternative secondary storage engine for dual-region deployments (#2914).
- Changed dual-region failover/failback to use the zone management API (#3482).
- Added OIDC authentication, Management Identity, Keycloak, and Camunda Hub to the single-region reference (#2917).
- Added optional Prometheus monitoring, benchmark load generation, and AWS FIS chaos procedures (#3457).
- Added OpenSearch authentication to the dual-region Orchestration Cluster (#3659).

### AWS EKS

- Added the single-region Aurora PostgreSQL secondary storage variant (#2724).
- Added the experimental multi-region RDBMS reference with Aurora Global Database and Submariner service discovery (#2940).
- Multi-region bootstrap now declares only running zones. New regions join through the zone management API (#3547).
- Multi-region service exports now address the chart's per-zone Zeebe Services (#3658, #3662).
- Replaced ingress-nginx with Project Contour in the single-region reference (#2623).
- Enabled encryption on gp3 EBS StorageClasses (#2189).
- Dual-region failback excludes Elasticsearch security feature state from snapshot restores to preserve credentials (#3335).

### AWS ROSA HCP and generic OpenShift

- Added a CloudNativePG secondary storage variant to the single-region ROSA reference (#2724).
- Added router TLS secret and HTTP/2 configuration procedures for gRPC access (#2400).
- Dual-region broker startup now waits for cross-region service DNS (#2627).

### Azure AKS

- Replaced ingress-nginx with Project Contour (#2689).
- Changed default node pools to Dsv6 and PostgreSQL Flexible Server compute to Dsv5 (#2843, #2848).
- Added retries for transient PostgreSQL provisioning failures (#3561).

### AWS EC2 and Debian

- Removed hardcoded demo credentials from service configuration templates (#2423).
- Added authenticated artifact downloads and corrected installation error handling (#2213, #2397).
- Migrated service configuration to unified `CAMUNDA_*` properties (#3501).

### Generic Kubernetes and local Kind

- Configured operator-managed PostgreSQL with two instances, required pod anti-affinity, and dedicated WAL volumes (#3463).
- Added a Keycloak readiness procedure to recover from transient OIDC discovery failures (#2718).

### Changed configuration and removed references

- Replaced standalone Console with Camunda Hub (#2842).
- Migrated Helm values to chart 15, including `global.host` and zone-aware `orchestration.partitioning` (#2418, #2424, #3441).
- Removed the Bitnami migration reference and its workflows. The 8.9 branch retains the migration tooling (#2587).
- Removed remaining ingress-nginx procedures and manifests after the Contour migration (#3410).
