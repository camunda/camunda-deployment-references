# Migration Guide from v1 to v2

## Key Changes
In the upgrade of the [AWS EKS Module v20](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest), there are significant changes to how AWS authentication is managed in the EKS module.

### Removed Parameters
- **aws_auth_roles** and **aws_auth_users**: These parameters have been removed from the module.

### AWS Auth ConfigMap Management
The management of `aws-auth` ConfigMap resources has been moved to a standalone sub-module. This change has the following implications:
- **No More Kubernetes Provider Requirement**: The main module no longer requires the Kubernetes provider.
- **Independent Management**: The `aws-auth` ConfigMap can now be managed independently of the main module.

### Our Decision
In our module, which primarily relies on the official AWS module, we have decided to remove the `aws-auth` ConfigMap directly, ahead of the decision made by the official module we rely on. This proactive approach aligns with the upcoming removal planned by the official module in the next major release.

### Migration Path
Please note that the official repository does not provide a specific migration path for this change. It is recommended to fork the repository and follow the official AWS instructions for managing the `aws-auth` ConfigMap.

For more details, please refer to the [official upgrade guide](https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/docs/UPGRADE-20.0.md).
