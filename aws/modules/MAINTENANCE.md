# MAINTENANCE.md

_This file serves as a reference for the maintenance procedures and guidelines for the EKS modules in this project._
_Note: Please keep this document updated with any changes in maintenance procedures, dependencies, actions, or restrictions._

## Maintenance Procedures

### Before New Releases

- Update documentation related to new features or changes.
    - `README.md`
    - Official Camunda documentation:
        - [C8SM: Amazon EKS](https://github.com/camunda/camunda-docs/blob/main/docs/self-managed/setup/deploy/amazon/amazon-eks/amazon-eks.md)
    - When releasing an update containing breaking changes, it should be accompanied by a migration guide in this repository to guide the user.

- Make internal announcements on Slack regarding upcoming releases.
    - `#infex-internal`
    - `#engineering` if relevant

- Refer to `DEVELOPER.md` to see the release process.

### After New Releases

_Nothing referenced yet._

## Dependencies

### Upstream Dependencies: dependencies of this project

- **terraform-aws-modules**: This project relies on the official AWS modules available at [terraform-aws-modules](https://github.com/terraform-aws-modules).

### Downstream Dependencies: things that depend on this project

- **c8-multi-region**: This project utilizes the EKS modules for multi-region deployment, available at [c8-multi-region](https://github.com/camunda/c8-multi-region).

## Actions

- Notify the **Product Management Team** of any new releases, especially if there are breaking changes or critical updates.

## Restrictions

- Never remove modules in the history of this repository, even if the sources are deprecated or removed.
