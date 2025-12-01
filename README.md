# Camunda Reference Architectures

[![Camunda](https://img.shields.io/badge/Camunda-FC5D0D)](https://www.camunda.com/)
[![Terraform](https://img.shields.io/badge/Terraform-5835CC)](https://developer.hashicorp.com/terraform/tutorials?product_intent=terraform)
[![License](https://img.shields.io/github/license/camunda/camunda-deployment-references)](LICENSE)

Welcome to Camunda Reference Architectures! This repository contains a collection of reference architectures for deploying [Camunda 8 self-managed](https://docs.camunda.io/docs/self-managed/about-self-managed/), implemented using Terraform, scripts, and GitHub Actions for testing.

These architectures serve as blueprints for quick learning and rapid deployment.

For more details, refer to the official [Camunda Reference Architecture documentation](https://docs.camunda.io/docs/self-managed/reference-architecture/).

The reference architecture implementations are intended for two main use cases:

1. **Reference**: Use these example implementations as guidance to help you build your own solution. Often, users bring their own infrastructure and simply need help with the missing components or confirmation of their existing setup.
2. **Copy & Paste**: You can copy these reference architectures as-is, using them as a starting point. Modify and extend them to meet your specific requirements.

**⚠️ Warning:** This project is intended for demonstration and learning purposes only. It is not recommended for production use. There are no guarantees or warranties provided, and certain Terraform configuration warnings from Trivy have been deliberately ignored. For more details, see the [.trivyignore](./.lint/trivy/.trivyignore) file in the repository root.

## Structure

The repository is organized into different cloud providers (`aws`, `azure`, `general`) and internal reusable modules (`modules`) that are associated with each cloud provider.

### Naming Convention

The directory structure follows a standardized naming pattern:

```
- {cloud_provider}
  - modules
  - {category}
    - {solution}-{feature}-{declination}
```

Where:
- `{cloud_provider}`: The cloud provider (`aws`, `azure`, `generic`).
- `{category}`: The type of service or technology (e.g., `kubernetes`, `compute`).
- `{solution}`: The specific solution, such as `eks` (Amazon EKS), `gke` (Google Kubernetes Engine), or `ec2` (Amazon EC2).
- `{feature}`: A specific feature or deployment model, particularly in relation to **Camunda 8**, such as:
  - `single-region` (deployment in a single region).
  - `dual-region` (high availability across two regions).
- `{declination}`: A variation of the solution, such as:
  - `spot-instances` (for EC2 cost optimization).
  - `on-demand` (for standard EC2 instances).

### Modules

The `modules` directory is tied to specific cloud providers. Each cloud provider may include reusable modules that can be utilized across multiple solutions within that cloud environment.

### Example Structure

For AWS Kubernetes and EC2 solutions:

```
- aws
  - kubernetes
    - eks-single-region
    - eks-single-region-spot-instances
    - eks-dual-region
    - eks-dual-region-karpenter
  - compute
    - ec2-single-region
    - ec2-single-region-spot-instances
  - modules
    - networking
    - monitoring
```

## Requirements

To manage the specific versions of this project, we use the following tools:

- **[asdf](https://asdf-vm.com/)** version manager (see the [installation guide](https://asdf-vm.com/guide/getting-started.html)).
- **[just](https://github.com/casey/just)** as a command runner
  You can install it using asdf with the following commands:
  ```bash
  asdf plugin add just
  asdf install just
  ```

### Installing Tooling

Once these tools are installed, you can set up the necessary tooling listed in the `.tool-versions` file located at the root of the project by running the following:

```bash
just install-tooling

# To list all available recipes:
just --list

# configure commit hooks
pre-commit install

```

## Support

Please note that the modules have been tested with **[Terraform](https://github.com/hashicorp/terraform)** in the version described in the [.tool-versions](./.tool-versions) of this project.

## Support & Feedback

Camunda Reference Architectures is maintained by Camunda Infrastructure Experience Team.

To provide feedback, please use the [issues templates](https://github.com/camunda/camunda-deployment-references/issues) provided.

If you are interested in contributing to Camunda Reference Architectures, see the [Contribution guide](https://github.com/camunda/camunda/blob/main/CONTRIBUTING.md).

## License

Apache-2.0 Licensed. See [LICENSE](https://github.com/camunda/camunda-deployment-references/blob/main/LICENSE).
