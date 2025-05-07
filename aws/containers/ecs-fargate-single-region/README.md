# ECS Fargate Single Region

> ⚠️ **WARNING: Do Not Use in Production**
>
> This setup is a **proof of concept** with hardcoded values, no persistent storage, and critical limitations in scalability and resilience.
> It lacks proper support for high availability and stateful workloads, and **should not be relied on for any production workloads**.

# Camunda on AWS ECS: Limitations and Observations

## Storage Limitations

- **Camunda does not support EFS.**
- **EBS support on AWS ECS is very limited**:
  - You cannot have persistent volumes.
  - Makes ECS **unsuitable for stateful applications**.

## ECS Suitability

- ECS is **ideal for stateless applications**.
- ECS **does not work well with Zeebe** due to lack of state persistence.

## ECS vs Kubernetes: A Perspective

| ECS Concept     | Kubernetes Equivalent          |
|----------------|---------------------------------|
| ECS Cluster     | Kubernetes Cluster              |
| ECS Service     | ReplicaSet + Service            |
| ECS Task        | Pod                             |

- **ECS Service**:
  - Defines the number of tasks to run.
  - Ensures desired task count is met.
  - Automatically restarts failed tasks.
  - Configures the Load Balancer (LB) target groups—acts similarly to a Kubernetes Service.

- **ECS Cluster**:
  - Can host multiple ECS Services, each spawning tasks.

- **ECS Task**:
  - Similar to a Docker Compose definition.
  - Can contain multiple containers (like a Kubernetes Pod).
  - Containers in the same task can communicate via `localhost` using exposed ports.

### Example Use Case
- Running Zeebe connectors and a single jar in one task definition:
  - They can communicate via `localhost`.
  - Ports must be properly exposed.

## Multi-Cluster Zeebe Setup in ECS

- You *could* define a multi-cluster Zeebe setup in a single ECS task, but:
  - **No resilience or high availability**.
  - **If the task dies, the entire Zeebe cluster goes down**.

### ECS Scaling Challenges

- ECS lacks a dynamic "index" feature to:
  - Automatically assign a `nodeId`.
  - Pass initial contact points for Zeebe.

### Alternative Approach

- **Instead of scaling one service to multiple tasks**:
  - Spawn **multiple ECS services**, each with **one task**.
  - Assign a **known nodeId** per service.
  - Use **AWS Cloud Map** for service discovery and communication.

## Current Implementation (CCON demo)

- A single Zeebe cluster setup (no multi-cluster due to time constraints).
- Quick PoC:
  - Hardcoded values in templates.
  - Similar to EC2 setup but using ECS Fargate.
  - Many unused variables remain.

## Known Issues

- **Connectors not working**:
  - Same configuration as EC2.
  - Connects to Zeebe / Operate.
  - **Fails to register webhooks** (unknown reason).

- **No persistent volume**:
  - Dummy init container resets DB.
  - Volume deleted each time a new task starts. Limitation of the platform.
