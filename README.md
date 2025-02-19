# Camunda Terraform EKS Modules

[![Camunda](https://img.shields.io/badge/Camunda-FC5D0D)](https://www.camunda.com/)
[![tests](https://github.com/camunda/camunda-tf-eks-module/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/camunda/camunda-tf-eks-module/actions/workflows/tests.yml)
[![License](https://img.shields.io/github/license/camunda/camunda-tf-eks-module)](LICENSE)

Terraform module which creates AWS EKS (Kubernetes) resources with an opinionated configuration targeting Camunda 8, an AWS Aurora RDS cluster and an OpenSearch domain.

**⚠️ Warning:** This project is not intended for production use but rather for demonstration purposes only. There are no guarantees or warranties provided. As such certain Terraform configuration warnings from Trivy have deliberately been ignored. For more details, see the [.trivyignore](./.trivyignore) file in the repository root.

## Documentation

The related [guide](https://docs.camunda.io/docs/next/self-managed/setup/deploy/amazon/amazon-eks/eks-terraform/) describes more detailed usage.
Consider installing Camunda 8 via [this guide](https://docs.camunda.io/docs/next/self-managed/setup/deploy/amazon/amazon-eks/eks-helm/) after deploying the AWS EKS cluster.

## Usage

### Example

Below is a simple example configuration for deploying both an EKS cluster, an Aurora PostgreSQL database and an OpenSearch domain.

See [AWS EKS Cluster inputs](./modules/eks-cluster/README.md#inputs), [AWS Aurora RDS inputs](./modules/aurora/README.md#inputs) and [AWS OpenSearch inputs](./modules/opensearch/README.md#inputs) for further configuration options and how they affect the cluster and database creation.

```hcl
module "eks_cluster" {
  source = "github.com/camunda/camunda-tf-eks-module/modules/eks-cluster"

  region             = "eu-central-1"
  name               = "cluster-name"

  cluster_service_ipv4_cidr = "10.190.0.0/16"
  cluster_node_ipv4_cidr    = "10.192.0.0/16"
}
```

```hcl
module "postgresql" {
  source                     = "github.com/camunda/camunda-tf-eks-module/modules/aurora"
  engine_version             = "15.4"
  auto_minor_version_upgrade = false
  cluster_name               = "cluster-name-postgresql"

  username         = "username"
  password         = "password"
  vpc_id           = module.eks_cluster.vpc_id
  subnet_ids       = module.eks_cluster.private_subnet_ids
  cidr_blocks      = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)
  instance_class   = "db.t3.medium"
  iam_auth_enabled = true

  depends_on = [module.eks_cluster]
}
```

```hcl

module "opensearch_domain" {
  source = "github.com/camunda/camunda-tf-eks-module/modules/opensearch"

  domain_name     = "my-opensearch-domain"
  subnet_ids      = module.eks_cluster.private_subnet_ids
  vpc_id          = module.eks_cluster.vpc_id
  cidr_blocks      = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)

  instance_type   = "m7i.large.search"
  instance_count  = 3
  ebs_volume_size = 100

  advanced_security_enabled = true
  advanced_security_internal_user_database_enabled = true
  advanced_security_master_user_name = "admin"
  advanced_security_master_user_password = "password"

  depends_on = [module.eks_cluster]
}
```

#### Deletion Known Issues

During the deletion process (`terraform destroy`) of the EKS Cluster, you may encounter an error message related to the `kubernetes_storage_class`:

````
Error: Get "http://localhost/apis/storage.k8s.io/v1/storageclasses/ebs-sc": dial tcp [::1]:80: connect: connection refused
│
│   with module.eks_cluster.kubernetes_storage_class_v1.ebs_sc,
│   on .terraform/modules/eks_cluster/modules/eks-cluster/cluster.tf line 156, in resource "kubernetes_storage_class_v1" "ebs_sc":
│  156: resource "kubernetes_storage_class_v1" "ebs_sc" {
│
╵
````

To resolve this issue, you can set the variable `create_ebs_gp3_default_storage_class` to `false`, which skips the creation of the `kubernetes_storage_class` resource. This helps to avoid dependency issues during deletion. Run the following command:

```bash
terraform destroy -var="create_ebs_gp3_default_storage_class=false"
```

If you still encounter the issue, you may need to manually remove the state for the storage class:

```bash
terraform state rm module.eks_cluster.kubernetes_storage_class_v1.ebs_sc
```

After performing these steps, re-run `terraform destroy` to complete the deletion process without further interruptions.

#### GitHub Actions

You can automate the deployment and deletion of the EKS cluster and Aurora database using GitHub Actions.

**Note:** This is recommended only for development and testing purposes, not for production use.

Below are examples of GitHub Actions workflows for deploying and deleting these resources.

For more details, refer to the corresponding [EKS Actions README](./.github/actions/eks-manage-cluster/README.md), [Aurora Actions README](./.github/actions/aurora-manage-cluster/README.md) and [OpenSearch Actions README](./.github/actions/opensearch-manage-cluster/README.md), [Cleanup Actions README](./.github/actions/eks-cleanup-resources/README.md).

An example workflow can be found in [here](./.github/workflows/test-gha-eks.yml).

#### Advanced usage with IRSA

This documentation provides a step-by-step guide to creating an EKS cluster, an Aurora RDS instance, and an OpenSearch domain with IRSA (IAM Roles for Service Accounts) roles using Terraform modules. The modules create the necessary IAM roles and policies for Aurora and OpenSearch. To simplify the configuration, the modules use the outputs of the EKS cluster module to define the IRSA roles and policies.

For further details and a more in-depth configuration, it is recommended to refer to the official documentation at:
- [Amazon EKS Terraform setup](https://docs.camunda.io/docs/self-managed/setup/deploy/amazon/amazon-eks/eks-terraform/)
- [IRSA roles setup](https://docs.camunda.io/docs/self-managed/setup/deploy/amazon/amazon-eks/irsa/)


### Aurora IRSA Role and Policy

The Aurora module uses the following outputs from the EKS cluster module to define the IRSA role and policy:

- `module.eks_cluster.oidc_provider_arn`: The ARN of the OIDC provider for the EKS cluster.
- `module.eks_cluster.oidc_provider_id`: The ID of the OIDC provider for the EKS cluster.
- `var.account_id`: Your AWS account id
- `var.aurora_region`: Your Aurora AWS Region
- `var.aurora_irsa_username`: The username used to access AuroraDB. This username is different from the superuser. The user must also be created manually in the database to enable the IRSA connection, as described in [the steps below](#create-irsa-user-on-the-database).
- `var.aurora_namespace`: The kubernetes namespace to allow access
- `var.aurora_service_account`: The kubernetes ServiceAccount to allow access

You need to define the IAM role trust policy and access policy for Aurora. Here's an example of how to define these policies using the outputs of the EKS cluster module:

```hcl
module "postgresql" {
  # ...
  iam_roles_with_policies = [
    {
      role_name = "AuroraRole-your-cluster" # ensure uniqueness of this one

      # Source: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html
      # Since the DbiResourceId may be unknown during the apply process, and because each instance of the RDS cluster contains its own DbiResourceId,
      # we use the wildcard `dbuser:*` to apply to all database instances.

      access_policy = <<EOF
            {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Effect": "Allow",
                  "Action": [
                    "rds-db:connect"
                  ],
                  "Resource": "arn:aws:rds-db:${var.aurora_region}:${var.account_id}:dbuser:*/${var.aurora_irsa_username}"
                }
              ]
            }
EOF

      trust_policy = <<EOF
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Principal": {
                  "Federated": "${module.eks_cluster.oidc_provider_arn}"
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                  "StringEquals": {
                    "${module.eks_cluster.oidc_provider_id}:sub": "system:serviceaccount:${var.aurora_namespace}:${var.aurora_service_account}"
                  }
                }
              }
            ]
          }
EOF
    }
  ]

  iam_auth_enabled = true
  # ...
}
```

#### Create IRSA User on the Database

Once the database is up, you will need to connect to it using the superuser credentials defined in the module (`username`, `password`).

```bash
echo "Creating IRSA DB user using admin user"
psql -h $AURORA_ENDPOINT -p $AURORA_PORT "sslmode=require dbname=$AURORA_DB_NAME user=$AURORA_USERNAME password=$AURORA_PASSWORD" \
  -c "CREATE USER \"${AURORA_USERNAME_IRSA}\" WITH LOGIN;" \
  -c "GRANT rds_iam TO \"${AURORA_USERNAME_IRSA}\";" \
  -c "GRANT ALL PRIVILEGES ON DATABASE \"${AURORA_DB_NAME}\" TO \"${AURORA_USERNAME_IRSA}\";" \
  -c "SELECT aurora_version();" \
  -c "SELECT version();" -c "\du"
```

The permissions can be adapted as needed. However, the most important permission is `rds_iam`, which is required for using IRSA with the database.

A complete example of a pod to [create the database is available](modules/fixtures/postgres-client.yml).

### OpenSearch IRSA Role and Policy

The OpenSearch module uses the following outputs from the EKS cluster module to define the IRSA role and policy:

- `module.eks_cluster.oidc_provider_arn`: The ARN of the OIDC provider for the EKS cluster.
- `module.eks_cluster.oidc_provider_id`: The ID of the OIDC provider for the EKS cluster.
- `var.account_id`: Your AWS account id
- `var.opensearch_region`: Your OpenSearch AWS Region
- `var.opensearch_domain_name`: The name of the OpenSearch domain to access
- `var.opensearch_namespace`: The kubernetes namespace to allow access
- `var.opensearch_service_account`: The kubernetes ServiceAccount to allow access

```hcl
module "opensearch_domain" {
  # ...
  iam_roles_with_policies = [
    {
      role_name = "OpenSearchRole-your-cluster" # ensure uniqueness of this one
      access_policy =<<EOF
            {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Effect": "Allow",
                  "Action": [
                    "es:ESHttpGet",
                    "es:ESHttpPut",
                    "es:ESHttpPost"
                  ],
                  "Resource": "arn:aws:es:${var.opensearch_region}:${var.account_id}:domain/${var.opensearch_domain_name}/*"
                }
              ]
            }
EOF

      trust_policy =  <<EOF
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Principal": {
                  "Federated": "${module.eks_cluster.oidc_provider_arn}"
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                  "StringEquals": {
                    "${module.eks_cluster.oidc_provider_id}:sub": "system:serviceaccount:${var.opensearch_namespace}:${var.opensearch_service_account}"
                  }
                }
              }
            ]
          }
EOF
    }
  ]

  # ...
}
```

By defining the IRSA roles and policies using the outputs of the EKS cluster module, you can simplify the configuration and ensure that the roles and policies are created with the correct permissions and trust policies.

Apply the Service Accounts definitions to your Kubernetes cluster:

**Aurora Service Account**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aurora-service-account
  namespace: <your-namespace>
  annotations:
    eks.amazonaws.com/role-arn: <arn:aws:iam:<YOUR-ACCOUNT-ID>:role/AuroraRole>
```
You can retrieve the role ARN from the module output: `aurora_iam_role_arns['Aurora-your-cluster']`.

**OpenSearch Service Account**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: opensearch-service-account
  namespace: <your-namespace>
  annotations:
    eks.amazonaws.com/role-arn: <arn:aws:iam:<YOUR-ACCOUNT-ID>:role/OpenSearchRole>
```
You can retrieve the role ARN from the module output: `opensearch_iam_role_arns['OpenSearch-your-cluster']`.

## Support

Please note that the modules have been tested with **[Terraform](https://github.com/hashicorp/terraform)** in the version described in the [.tool-versions](./.tool-versions) of this project.
