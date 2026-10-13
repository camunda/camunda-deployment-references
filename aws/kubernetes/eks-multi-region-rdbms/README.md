# EKS multi-region with RDBMS secondary storage – Camunda 8 reference architecture

> [!WARNING]
> This reference architecture is experimental and intended for learning,
> evaluation, and design review. It is not production-ready.

This folder describes the setup of Camunda 8 on AWS EKS across three or more
regions, where Zeebe keeps quorum after a region is lost and an RDBMS handles
secondary-storage replication and writer failover.

The [Camunda 8.10 deployment procedure](https://docs.camunda.io/docs/8.10/self-managed/deployment/helm/cloud-providers/amazon/amazon-eks/multi-region-rdbms/) describes the installation steps.

The [multi-region RDBMS operations guide](https://docs.camunda.io/docs/8.10/self-managed/deployment/helm/operational-tasks/multi-region-rdbms-operational-procedure/) describes day-2 operations, failover, and failback.
