# Deploy AWS ROSA HCP Dual Region Cluster

## Description

This GitHub Action automates the deployment of the aws/openshift/rosa-hcp-dual-region reference architecture cluster using Terraform.
It will create 2 OpenShift clusters, a VPC peering accross the regions and a backup bucket.
This action will also install oc, awscli, rosa cli.
Each cluster will be added to the kube config with the name of the cluster as context's name.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `rh-token` | <p>Red Hat Hybrid Cloud Console Token</p> | `true` | `""` |
| `cluster-name-1` | <p>Name of the ROSA cluster 1 to deploy</p> | `true` | `""` |
| `cluster-name-2` | <p>Name of the ROSA cluster 2 to deploy</p> | `true` | `""` |
| `admin-password-cluster-1` | <p>Admin password for the ROSA cluster 1</p> | `true` | `""` |
| `admin-username-cluster-1` | <p>Admin username for the ROSA cluster 1</p> | `false` | `kube-admin` |
| `admin-password-cluster-2` | <p>Admin password for the ROSA cluster 2</p> | `true` | `""` |
| `admin-username-cluster-2` | <p>Admin username for the ROSA cluster 2</p> | `false` | `kube-admin` |
| `aws-region-cluster-1` | <p>AWS region where the ROSA cluster 1 will be deployed</p> | `true` | `""` |
| `aws-region-cluster-2` | <p>AWS region where the ROSA cluster 2 will be deployed</p> | `true` | `""` |
| `availability-zones-cluster-1` | <p>Comma separated list of availability zones for cluster 1 (letters only, e.g., a,b,c)</p> | `false` | `a,b,c` |
| `availability-zones-cluster-2` | <p>Comma separated list of availability zones for cluster 2 (letters only, e.g., a,b,c)</p> | `false` | `a,b,c` |
| `rosa-cli-version` | <p>Version of the ROSA CLI to use</p> | `false` | `latest` |
| `openshift-version-cluster-1` | <p>Version of the OpenShift to install</p> | `false` | `4.20.3` |
| `openshift-version-cluster-2` | <p>Version of the OpenShift to install</p> | `false` | `4.20.3` |
| `replicas-cluster-1` | <p>Number of replicas for the ROSA cluster 1 (empty will fallback on default value of the module)</p> | `false` | `""` |
| `replicas-cluster-2` | <p>Number of replicas for the ROSA cluster 2 (empty will fallback on default value of the module)</p> | `false` | `""` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states.</p> | `true` | `""` |
| `s3-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the tf modules to use</p> | `false` | `main` |
| `tf-modules-path` | <p>Path where the tf rosa modules will be cloned</p> | `false` | `./.action-tf-modules/aws-openshift-rosa-hcp-dual-region-create/` |
| `login` | <p>Authenticate the current kube context on the created clusters</p> | `false` | `true` |
| `enable-vpc-peering` | <p>Whether or not to enable VPC Peering between the clusters</p> | `false` | `true` |
| `enable-backup-bucket` | <p>Whether or not to enable Backup Bucket creation used by the clusters</p> | `false` | `true` |
| `cleanup-tf-modules-path` | <p>Whether to clean up the tf modules path</p> | `false` | `false` |
| `tags` | <p>Tags to apply to the cluster and related resources, in JSON format</p> | `false` | `{}` |


## Outputs

| name | description |
| --- | --- |
| `openshift-server-api-cluster-1` | <p>The server API URL of the deployed ROSA cluster 1</p> |
| `openshift-server-api-cluster-2` | <p>The server API URL of the deployed ROSA cluster 2</p> |
| `openshift-cluster-id-cluster-1` | <p>The ID of the deployed ROSA cluster 1</p> |
| `openshift-cluster-id-cluster-2` | <p>The ID of the deployed ROSA cluster 2</p> |
| `openshift-cluster-vpc-id-cluster-1` | <p>The VPC ID of the deployed ROSA cluster 1</p> |
| `openshift-cluster-vpc-id-cluster-2` | <p>The VPC ID of the deployed ROSA cluster 2</p> |
| `backup-bucket-s3-aws-access-key` | <p>The AWS Access Key of the S3 Backup bucket used by Camunda</p> |
| `backup-bucket-s3-aws-secret-access-key` | <p>The AWS Secret Access Key of the S3 Backup bucket used by Camunda</p> |
| `backup-bucket-s3-bucket-name` | <p>The name of the S3 Backup bucket used by Camunda</p> |
| `terraform-state-url-clusters` | <p>URL of the module "clusters" Terraform state file in the S3 bucket</p> |
| `terraform-state-url-peering` | <p>URL of the module "peering" Terraform state file in the S3 bucket</p> |
| `terraform-state-url-backup-bucket` | <p>URL of the module "backup-bucket" Terraform state file in the S3 bucket</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-openshift-rosa-hcp-dual-region-create@main
  with:
    rh-token:
    # Red Hat Hybrid Cloud Console Token
    #
    # Required: true
    # Default: ""

    cluster-name-1:
    # Name of the ROSA cluster 1 to deploy
    #
    # Required: true
    # Default: ""

    cluster-name-2:
    # Name of the ROSA cluster 2 to deploy
    #
    # Required: true
    # Default: ""

    admin-password-cluster-1:
    # Admin password for the ROSA cluster 1
    #
    # Required: true
    # Default: ""

    admin-username-cluster-1:
    # Admin username for the ROSA cluster 1
    #
    # Required: false
    # Default: kube-admin

    admin-password-cluster-2:
    # Admin password for the ROSA cluster 2
    #
    # Required: true
    # Default: ""

    admin-username-cluster-2:
    # Admin username for the ROSA cluster 2
    #
    # Required: false
    # Default: kube-admin

    aws-region-cluster-1:
    # AWS region where the ROSA cluster 1 will be deployed
    #
    # Required: true
    # Default: ""

    aws-region-cluster-2:
    # AWS region where the ROSA cluster 2 will be deployed
    #
    # Required: true
    # Default: ""

    availability-zones-cluster-1:
    # Comma separated list of availability zones for cluster 1 (letters only, e.g., a,b,c)
    #
    # Required: false
    # Default: a,b,c

    availability-zones-cluster-2:
    # Comma separated list of availability zones for cluster 2 (letters only, e.g., a,b,c)
    #
    # Required: false
    # Default: a,b,c

    rosa-cli-version:
    # Version of the ROSA CLI to use
    #
    # Required: false
    # Default: latest

    openshift-version-cluster-1:
    # Version of the OpenShift to install
    #
    # Required: false
    # Default: 4.20.3

    openshift-version-cluster-2:
    # Version of the OpenShift to install
    #
    # Required: false
    # Default: 4.20.3

    replicas-cluster-1:
    # Number of replicas for the ROSA cluster 1 (empty will fallback on default value of the module)
    #
    # Required: false
    # Default: ""

    replicas-cluster-2:
    # Number of replicas for the ROSA cluster 2 (empty will fallback on default value of the module)
    #
    # Required: false
    # Default: ""

    s3-backend-bucket:
    # Name of the S3 bucket to store Terraform state
    #
    # Required: true
    # Default: ""

    s3-bucket-region:
    # Region of the bucket containing the resources states.
    #
    # Required: true
    # Default: ""

    s3-bucket-key-prefix:
    # Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.
    #
    # Required: false
    # Default: ""

    tf-modules-revision:
    # Git revision of the tf modules to use
    #
    # Required: false
    # Default: main

    tf-modules-path:
    # Path where the tf rosa modules will be cloned
    #
    # Required: false
    # Default: ./.action-tf-modules/aws-openshift-rosa-hcp-dual-region-create/

    login:
    # Authenticate the current kube context on the created clusters
    #
    # Required: false
    # Default: true

    enable-vpc-peering:
    # Whether or not to enable VPC Peering between the clusters
    #
    # Required: false
    # Default: true

    enable-backup-bucket:
    # Whether or not to enable Backup Bucket creation used by the clusters
    #
    # Required: false
    # Default: true

    cleanup-tf-modules-path:
    # Whether to clean up the tf modules path
    #
    # Required: false
    # Default: false

    tags:
    # Tags to apply to the cluster and related resources, in JSON format
    #
    # Required: false
    # Default: {}
```
