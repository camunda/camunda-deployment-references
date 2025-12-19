# ECS single-region (Fargate) – Camunda 8 reference architecture

This reference architecture deploys Camunda 8 (self-managed) to **AWS ECS on Fargate** in a **single region**, fronted by an **ALB** (HTTP) and **NLB** (gRPC), with **Aurora PostgreSQL** as RDBMS and supporting AWS primitives (EFS, S3, CloudWatch Logs, Secrets Manager, KMS).

> ⚠️ This repository is intended for demonstration and learning purposes. This readme is temporary and will eventually be converted to camunda-docs.

## What this stack includes

From the Terraform in [aws/containers/ecs-single-region-fargate/terraform](terraform):

- **Networking**: VPC (3 AZs), public/private subnets, a single NAT gateway.
- **Compute**: One ECS cluster with **Container Insights enabled**.
- **Core services**:
  - **Orchestration Cluster**: Camunda “core” component(s) deployed as a Fargate ECS service.
  - **Connectors**: Camunda Connectors bundle deployed as a separate ECS service.
- **Load balancing**:
  - **ALB** (public) for HTTP traffic (UI/REST + path routing).
  - **NLB** (public) for **Zeebe gateway gRPC** traffic.
- **Data**:
  - **Aurora PostgreSQL** cluster for Camunda’s secondary storage usage.
  - **EFS** for the Zeebe broker data directory.
  - **S3** bucket used by the orchestration cluster’s ECS-specific node ID provider.
- **Secrets & crypto**:
  - **AWS Secrets Manager** for application credentials and optional container registry credentials.
  - A **customer-managed KMS key** (or an optional existing key) for Secrets Manager encryption.
- **Observability**:
  - CloudWatch log group(s) for services.

### Exposed endpoints

- **ALB :80**
  - `/*` routes to the orchestration cluster UI/REST (target group port 8080).
  - `/connectors*` routes to the connectors service (target group port 8080).
- **ALB :9600**
  - Exposes the management/metrics port (used for health checks and optionally accessible externally depending on `limit_access_to_cidrs`).
  - For debugging purposes and will be disabled as it should not be publicly accessible.
- **NLB :26500 (TCP)**
  - Exposes Zeebe gateway gRPC.

## ECS specifics

Camunda is trying to utilize the native capabilities of ECS fargate. Meaning using a single service for the Orchestration Cluster instead of a service per broker.

The Orchestration Cluster is due to the Zeebe Cluster a stateful application, therefore requires some workarounds for a primarily stateless platform.

A S3 bucket is utilized for metadata management of the new node id provider that will allow the Zeebe brokers to agree on id assignment to ensure no id is assigned twice.

The EFS volume is shared among all brokers to again support the easy use of ECS services and their scalability.

Scalability will remain a manual process though as it requires user intervention by extending the Zeebe cluster via the Cluster scaling API.

ECS wise we're utilizing the inbuilt service mesh by using ECS service connect. The previously common DNS exposure is still done for the Orchestration Cluster to allow DNS resolving and ease of use outside of ECS.

The service connect acts similar to a multi defined A record. Zeebe will retrieve all saved IPs behind the DNS name. It's similar to a headless service in Kubernetes.

## Terraform specifics

The root workspace houses the overall implementation to keep things configurable and interchangeable as needed.

- VPC
- IAM
- Security groups
- ECS Cluster
- Aurora Postgres
  - optional seeding task
- LoadBalancer
- Secrets (+ KMS)

The ECS related modules focus solely on their application specific configuration and usage with just covering the sole base required for ECS. Any additional required configuration should be managed by the user.

For the Orchestration Cluster:

- Creates IAM task role specific to this task access
  - not to confuse with the task execution role. This is just scoped to what the task is allowed to access (S3 / Postgres)
- Creates required S3 bucket for the node id provider
- EFS volume
- LoadBalancer rules for ALB and proper listener for NLB
  - just rules for ALB since the ALB is shared among applications so each application can add their ALB rule
  - this allows to have `/connectors` and `/operate`, ... all within the same ALB and port.
- Orchestration Cluster acts as primary required module, you wouldn't run Camunda without it
  - DNS namespace
  - CloudWatch group
- ECS Service + ECS Task definition
- Application specific configuration
  - node id provider
  - Zeebe cluster size based on the task size
  - Zeebe data folder
  - Zeebe initial contact points (the previously mentioned service connect)

For the Connectors:

- Creates IAM task role specific to this task access
- LoadBalancer rules for ALB
- ECS Service + ECS Task definition

## Terraform flow

Terraform will first create the base requirements

- ECS Cluster
- VPC
- Security groups
- IAM
- Aurora Postgres

After those are done, Terraform will do a local execution to do the initial seeding for IAM auth of the Aurora Postgres via an ECS task. Everything is in private subnets so it's not easily reachable for the end user without workarounds.

Alternative implementation choices to local exec:

- 3 Step setup via separate workspaces
  - base requirements
  - db seeding for IAM auth
  - Camunda ECS services
- Lambda functions
- Step functions

If one is not using IAM auth for Aurora Postgres it can be fully skipped and directly consume the master username / password for the setup.

The Camunda services have wait for completion enabled which may seem time consuming but it ensures that Connectors starts after the Orchestration Cluster is healthy as it has a direct dependency on it and otherwise keeps crashlooping.
One can disable this setting by setting `wait_for_steady_state` false for the module usage.

## Deployment & operations

### Prerequisites

- Terraform `>= 1.7.0`
- AWS credentials available to Terraform (e.g., `AWS_PROFILE`, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`)
- AWS CLI installed if `db_seed_enabled=true` (Terraform will run `aws ecs run-task` locally)

### Quickstart

1. Go to the Terraform root:

   - `aws/containers/ecs-single-region-fargate/terraform`

2. Adjust inputs via `*.tfvars` and/or CLI `-var` flags.

3. Run:

   - `terraform init`
   - `terraform plan -out plan.tfplan`
   - `terraform apply plan.tfplan`

4. Use Terraform outputs:

- `alb_endpoint` (UI/REST)
- `nlb_endpoint` (gRPC)
- `admin_user_password` (generated and stored in Secrets Manager)
  - can be exposed via `terraform output -raw admin_user_password` for direct usage

### Rolling deployments & availability behavior

- Orchestration cluster uses a deployment policy intended to maintain quorum:
  - `deployment_minimum_healthy_percent = 66`
  - `deployment_maximum_percent = 100`

### ECS Exec

Both services support ECS Exec (enabled by default - atm for debugging purposes). Ensure your IAM permissions for your local user or role allow `ecs:ExecuteCommand` and that SSM messaging permissions are in place.

## Production hardening checklist (starting point)

- Terminate TLS at the ALB (HTTPS listener + ACM cert) and restrict HTTP.
- Do not expose port `9600` publicly; keep it internal-only.
- Replace the local Terraform backend with a remote backend (e.g., S3 + DynamoDB lock).
- Restrict `limit_access_to_cidrs` to trusted networks.
- Enable ALB/NLB access logs, S3 bucket versioning/logging as required.
- Review EFS throughput mode and sizing.
