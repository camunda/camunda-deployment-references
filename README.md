# Camunda Reference Architectures

[![Camunda](https://img.shields.io/badge/Camunda-FC5D0D)](https://www.camunda.com/)
[![License](https://img.shields.io/github/license/camunda/camunda-deployment-references)](LICENSE)

Welcome to Camunda Reference Architectures! This repository contains a collection of reference architectures for deploying Camunda 8 self-managed, implemented using Terraform, scripts, and GitHub Actions for testing.

These architectures serve as blueprints for quick learning and rapid deployment.

For more details, refer to the official [Camunda Reference Architecture documentation](https://docs.camunda.io/docs/8.7/self-managed/reference-architecture/).

**⚠️ Warning:** This project is intended for demonstration and learning purposes only. It is not recommended for production use. There are no guarantees or warranties provided, and certain Terraform configuration warnings from Trivy have been deliberately ignored. For more details, see the [.trivyignore](./.trivyignore) file in the repository root.

## Structure

The repository is structured into cloud providers (`aws`, `azure`, `general`) and internal-only reusable modules (`modules`).

## Support

Please note that the modules have been tested with **[Terraform](https://github.com/hashicorp/terraform)** in the version described in the [.tool-versions](./.tool-versions) of this project.

## Support & Feedback

Camunda Reference Architectures is maintained by Camunda Infrastructure Experience Team.

To provide feedback, please use the [issues templates](https://github.com/camunda/camunda-deployment-references/issues) provided.

If you are interested in contributing to Camunda Reference Architectures, see the [Contribution guide](https://github.com/camunda/camunda/blob/main/CONTRIBUTING.md).

## License

Apache-2.0 Licensed. See [LICENSE](https://github.com/camunda/camunda-deployment-references/blob/main/LICENSE).
