# EKS multi-region with RDBMS secondary storage – Camunda 8 reference architecture

> [!WARNING]
> This reference architecture is experimental and intended for learning,
> evaluation, and design review. It is not production-ready.

This folder describes the setup of Camunda 8 on AWS EKS across three or more
regions, where Zeebe keeps quorum after a region is lost and an RDBMS handles
secondary-storage replication and writer failover.

Instructions can be found on the official documentation: https://docs.camunda.io/docs/next/self-managed/deployment/helm/cloud-providers/amazon/amazon-eks/multi-region-rdbms/

Day-2 operations, failover and failback are documented in [multi-region RDBMS operations](https://docs.camunda.io/docs/next/self-managed/deployment/helm/operational-tasks/multi-region-rdbms-ops/).
