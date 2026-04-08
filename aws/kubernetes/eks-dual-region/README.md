# EKS dual-region – Camunda 8 reference architecture

This folder describes the Setup of Camunda on AWS EKS in a dual-region setup.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/self-managed/deployment/helm/cloud-providers/amazon/amazon-eks/dual-region/

## Connectivity Options

By default, this reference architecture uses **VPC Peering** to connect the two regional VPCs. You can alternatively use an **AWS Transit Gateway** by setting the `connectivity_type` variable.

### VPC Peering (default)

No additional configuration needed. The peering connection is created and managed by Terraform.

### Transit Gateway

Requires a pre-existing Transit Gateway. Set the following variables:

```hcl
connectivity_type  = "transit-gateway"
transit_gateway_id = "tgw-0123456789abcdef0"  # your existing TGW ID
```

For cross-account Transit Gateway (e.g., in an enterprise landing zone with a shared networking account):

```hcl
connectivity_type            = "transit-gateway"
transit_gateway_id           = "tgw-0123456789abcdef0"
transit_gateway_ram_share_arn = "arn:aws:ram:eu-west-2:123456789012:resource-share/abc-123"
```
