# Deploy AWS ROSA HCP Single Region Cluster

## Description

This GitHub Action automates the deployment of the aws/openshift/rosa-hcp-single-region reference architecture cluster using Terraform.
This action will also install oc, awscli, rosa cli.
The kube context will be set on the created cluster.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `rh-token` | <p>Red Hat Hybrid Cloud Console Token</p> | `true` | `""` |
| `cluster-name` | <p>Name of the ROSA cluster to deploy</p> | `true` | `""` |
| `admin-password` | <p>Admin password for the ROSA cluster</p> | `true` | `""` |
| `admin-username` | <p>Admin username for the ROSA cluster</p> | `true` | `kube-admin` |
| `aws-region` | <p>AWS region where the ROSA cluster will be deployed</p> | `true` | `""` |
| `availability-zones` | <p>Comma separated list of availability zones (letters only, e.g., a,b,c)</p> | `true` | `a,b,c` |
| `rosa-cli-version` | <p>Version of the ROSA CLI to use</p> | `true` | `latest` |
| `openshift-version` | <p>Version of the OpenShift to install</p> | `true` | `4.17.16` |
| `replicas` | <p>Number of replicas for the ROSA cluster (empty will fallback on default value of the module)</p> | `false` | `""` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on aws-region</p> | `false` | `""` |
| `s3-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the tf modules to use</p> | `true` | `main` |
| `tf-modules-path` | <p>Path where the tf rosa modules will be cloned</p> | `true` | `./.action-tf-modules/aws-openshift-rosa-hcp-single-region-create/` |
| `login` | <p>Authenticate the current kube context on the created cluster</p> | `true` | `true` |


## Outputs

| name | description |
| --- | --- |
| `openshift-server-api` | <p>The server API URL of the deployed ROSA cluster</p> |
| `openshift-cluster-id` | <p>The ID of the deployed ROSA cluster</p> |
| `terraform-state-url` | <p>URL of the Terraform state file in the S3 bucket</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-openshift-rosa-hcp-single-region-create@main
  with:
    rh-token:
    # Red Hat Hybrid Cloud Console Token
    #
    # Required: true
    # Default: ""

    cluster-name:
    # Name of the ROSA cluster to deploy
    #
    # Required: true
    # Default: ""

    admin-password:
    # Admin password for the ROSA cluster
    #
    # Required: true
    # Default: ""

    admin-username:
    # Admin username for the ROSA cluster
    #
    # Required: true
    # Default: kube-admin

    aws-region:
    # AWS region where the ROSA cluster will be deployed
    #
    # Required: true
    # Default: ""

    availability-zones:
    # Comma separated list of availability zones (letters only, e.g., a,b,c)
    #
    # Required: true
    # Default: a,b,c

    rosa-cli-version:
    # Version of the ROSA CLI to use
    #
    # Required: true
    # Default: latest

    openshift-version:
    # Version of the OpenShift to install
    #
    # Required: true
    # Default: 4.17.16

    replicas:
    # Number of replicas for the ROSA cluster (empty will fallback on default value of the module)
    #
    # Required: false
    # Default: ""

    s3-backend-bucket:
    # Name of the S3 bucket to store Terraform state
    #
    # Required: true
    # Default: ""

    s3-bucket-region:
    # Region of the bucket containing the resources states, if not set, will fallback on aws-region
    #
    # Required: false
    # Default: ""

    s3-bucket-key-prefix:
    # Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.
    #
    # Required: false
    # Default: ""

    tf-modules-revision:
    # Git revision of the tf modules to use
    #
    # Required: true
    # Default: main

    tf-modules-path:
    # Path where the tf rosa modules will be cloned
    #
    # Required: true
    # Default: ./.action-tf-modules/aws-openshift-rosa-hcp-single-region-create/

    login:
    # Authenticate the current kube context on the created cluster
    #
    # Required: true
    # Default: true
```
