# MAINTENANCE.md

_This file serves as a reference for the maintenance procedures and guidelines for the EKS modules in this project._
_Note: Please keep this document updated with any changes in maintenance procedures, dependencies, actions, or restrictions._

## Maintenance Procedures

## Dependencies

### Upstream Dependencies: dependencies of this project

- **terraform-aws-modules**: This project relies on the official AWS modules available at [terraform-aws-modules](https://github.com/terraform-aws-modules).

### Downstream Dependencies: things that depend on this project

- **c8-multi-region**: This project utilizes the EKS modules for multi-region deployment, available at [c8-multi-region](https://github.com/camunda/c8-multi-region).

## Actions

## Restrictions

- Never remove modules in the history of this repository, even if the sources are deprecated or removed.
