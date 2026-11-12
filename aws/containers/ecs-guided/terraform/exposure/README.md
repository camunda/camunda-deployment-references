# Exposure stage

The ALB and the gRPC NLB, optional TLS through an ACM certificate you provide. It creates no routing rules: the components attach their own to the listeners in its outputs. Creating the DNS record for `alb_public_hostname` is up to you.

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb.grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.raft](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http_management](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_webapp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https_webapp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.http_to_https_redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_security_group.remote_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.remote_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.remote_grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_certificate_arn"></a> [alb\_certificate\_arn](#input\_alb\_certificate\_arn) | ACM certificate ARN. When set, the ALB serves HTTPS on 443 and HTTP on 80 redirects to it. Empty keeps plain HTTP on 80, for a demo. | `string` | `""` | no |
| <a name="input_alb_public_hostname"></a> [alb\_public\_hostname](#input\_alb\_public\_hostname) | DNS name clients use to reach the ALB (for example an alias record you create). Required with alb\_certificate\_arn: ACM cannot issue a certificate for the ALB's own *.elb.amazonaws.com name. Empty falls back to the ALB's DNS name. | `string` | `""` | no |
| <a name="input_alb_ssl_policy"></a> [alb\_ssl\_policy](#input\_alb\_ssl\_policy) | SSL negotiation policy of the HTTPS listener (used only when alb\_certificate\_arn is set) | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| <a name="input_camunda_ports_security_group_id"></a> [camunda\_ports\_security\_group\_id](#input\_camunda\_ports\_security\_group\_id) | Compute stage output: security group that opens the Camunda ports inside the VPC | `string` | n/a | yes |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_enable_raft_nlb"></a> [enable\_raft\_nlb](#input\_enable\_raft\_nlb) | Create an internal network load balancer for the cluster's internal traffic (26502). A second region's brokers join the cluster through it. Set it to true from the start if you expect to add a region: adding it later makes the Camunda stage register a target group on an existing ECS service, which Terraform may replace. | `bool` | `false` | no |
| <a name="input_limit_access_to_cidrs"></a> [limit\_access\_to\_cidrs](#input\_limit\_access\_to\_cidrs) | CIDR blocks allowed to reach the load balancers. The default is open to the internet: restrict it. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Network stage output: private subnet IDs. Required when enable\_raft\_nlb = true. | `list(string)` | `[]` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Network stage output: public subnet IDs for the internet-facing load balancers | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Network stage output: ID of the VPC | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the ALB. Point your public hostname at it. |
| <a name="output_alb_listener_http_management_arn"></a> [alb\_listener\_http\_management\_arn](#output\_alb\_listener\_http\_management\_arn) | Listener on 9600 for the management endpoints. The Camunda stage leaves its rule off by default: the endpoint is unauthenticated. |
| <a name="output_alb_listener_http_webapp_arn"></a> [alb\_listener\_http\_webapp\_arn](#output\_alb\_listener\_http\_webapp\_arn) | Listener for the web apps and OIDC callbacks: HTTPS 443 when a certificate is set, HTTP 80 otherwise |
| <a name="output_nlb_grpc_arn"></a> [nlb\_grpc\_arn](#output\_nlb\_grpc\_arn) | ARN of the network load balancer for gRPC (26500) |
| <a name="output_nlb_grpc_dns_name"></a> [nlb\_grpc\_dns\_name](#output\_nlb\_grpc\_dns\_name) | DNS name of the gRPC network load balancer |
| <a name="output_nlb_raft_arn"></a> [nlb\_raft\_arn](#output\_nlb\_raft\_arn) | ARN of the internal network load balancer for broker traffic, empty unless enable\_raft\_nlb is set |
| <a name="output_nlb_raft_dns_name"></a> [nlb\_raft\_dns\_name](#output\_nlb\_raft\_dns\_name) | DNS name of the internal network load balancer for broker traffic, empty unless enable\_raft\_nlb is set. The other region uses it as an initial contact point. |
| <a name="output_public_base_url"></a> [public\_base\_url](#output\_public\_base\_url) | Browser-facing base URL (scheme and host). OIDC redirect URIs and issuers are built from it. |
<!-- END_TF_DOCS -->
