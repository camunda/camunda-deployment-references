# vpn

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_acm_certificate.ca_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate.vpn_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_cloudwatch_log_group.vpn_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_stream.vpn_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_stream) | resource |
| [aws_ec2_client_vpn_authorization_rule.vpn_auth_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_client_vpn_authorization_rule) | resource |
| [aws_ec2_client_vpn_endpoint.vpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_client_vpn_endpoint) | resource |
| [aws_ec2_client_vpn_network_association.vpn_subnet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_client_vpn_network_association) | resource |
| [aws_kms_key.certs_encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_object.upload_ca_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_ca_public_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_client_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_client_public_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_server_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_server_public_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_vpn_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_security_group.vpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [local_file.vpn_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [null_resource.cleanup_certs](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.cleanup_client_configs](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.cleanup_downloaded_ca_files](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.cleanup_downloaded_certs](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.download_certs](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.download_existing_ca](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.download_server_and_ca_certs](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.wait_for_ca_download](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.wait_for_cert_download](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.wait_for_cert_download_client](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [tls_cert_request.client_csr](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/cert_request) | resource |
| [tls_cert_request.server_csr](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/cert_request) | resource |
| [tls_locally_signed_cert.client_public_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/locally_signed_cert) | resource |
| [tls_locally_signed_cert.server_public_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/locally_signed_cert) | resource |
| [tls_private_key.ca_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.client_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.server_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.ca_public_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [local_file.ca_cert](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.ca_private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.client_cert](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.client_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.existing_ca_cert](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.existing_ca_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.server_cert](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.server_private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ca_common_name"></a> [ca\_common\_name](#input\_ca\_common\_name) | Common Name (CN) field for the CA certificate | `string` | `"common.local"` | no |
| <a name="input_ca_early_renewal_hours"></a> [ca\_early\_renewal\_hours](#input\_ca\_early\_renewal\_hours) | Time before CA certificate expiration to renew it, in hours (default: 30 days) | `number` | `720` | no |
| <a name="input_ca_key_algorithm"></a> [ca\_key\_algorithm](#input\_ca\_key\_algorithm) | Algorithm used to generate the CA private key | `string` | `"RSA"` | no |
| <a name="input_ca_key_bits"></a> [ca\_key\_bits](#input\_ca\_key\_bits) | Key size in bits for the CA private key | `number` | `4096` | no |
| <a name="input_ca_organization"></a> [ca\_organization](#input\_ca\_organization) | Organization name for the CA certificate | `string` | `"Organization CA VPN"` | no |
| <a name="input_ca_validity_period_hours"></a> [ca\_validity\_period\_hours](#input\_ca\_validity\_period\_hours) | Validity period of the CA certificate in hours (default: 10 years) | `number` | `87600` | no |
| <a name="input_client_certificate_validity_period_hours"></a> [client\_certificate\_validity\_period\_hours](#input\_client\_certificate\_validity\_period\_hours) | Validity period of client certificates in hours (default: 1 year) | `number` | `8760` | no |
| <a name="input_client_key_names"></a> [client\_key\_names](#input\_client\_key\_names) | List of client key names to generate certificates for | `list(string)` | n/a | yes |
| <a name="input_key_algorithm"></a> [key\_algorithm](#input\_key\_algorithm) | Algorithm used to generate private keys (client, server) | `string` | `"RSA"` | no |
| <a name="input_key_bits"></a> [key\_bits](#input\_key\_bits) | Key size in bits for private keys (client, server) | `number` | `2048` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Name of the KMS key used for encrypting certificates and keys in S3 | `string` | `"vpn-certs-kms-key"` | no |
| <a name="input_s3_bucket_name"></a> [s3\_bucket\_name](#input\_s3\_bucket\_name) | Name of the bucket that stores the certificates and keys | `string` | n/a | yes |
| <a name="input_s3_ca_directory"></a> [s3\_ca\_directory](#input\_s3\_ca\_directory) | Directory name inside the S3 bucket where CA and certificates are stored | `string` | `"my-ca"` | no |
| <a name="input_server_certificate_validity_period_hours"></a> [server\_certificate\_validity\_period\_hours](#input\_server\_certificate\_validity\_period\_hours) | Validity period of server certificates in hours (default: 1 year) | `number` | `8760` | no |
| <a name="input_server_common_name"></a> [server\_common\_name](#input\_server\_common\_name) | Common Name (CN) field for the server certificate | `string` | `"server.common.local"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to access from the VPN | `string` | n/a | yes |
| <a name="input_vpc_subnet_ids"></a> [vpc\_subnet\_ids](#input\_vpc\_subnet\_ids) | List of subnets to access | `set(string)` | n/a | yes |
| <a name="input_vpc_target_network_cidr"></a> [vpc\_target\_network\_cidr](#input\_vpc\_target\_network\_cidr) | CIDR of the target network to access | `string` | n/a | yes |
| <a name="input_vpn_allowed_cidr_blocks"></a> [vpn\_allowed\_cidr\_blocks](#input\_vpn\_allowed\_cidr\_blocks) | List of CIDR blocks that are allowed to access the Client VPN endpoint on UDP port 443. Use caution when allowing wide access (e.g., 0.0.0.0/0). | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_vpn_client_banner"></a> [vpn\_client\_banner](#input\_vpn\_client\_banner) | Banner to display to the users of the VPN | `string` | `"This VPN is for authorized users only. All activities may be monitored and recorded."` | no |
| <a name="input_vpn_client_cidr"></a> [vpn\_client\_cidr](#input\_vpn\_client\_cidr) | Client CIDR, it must be different from the primary VPC CIDR | `string` | `"172.0.0.0/22"` | no |
| <a name="input_vpn_cloudwatch_log_group_retention"></a> [vpn\_cloudwatch\_log\_group\_retention](#input\_vpn\_cloudwatch\_log\_group\_retention) | Number of days of retention to keep vpn logs | `number` | `365` | no |
| <a name="input_vpn_endpoint_dns_servers"></a> [vpn\_endpoint\_dns\_servers](#input\_vpn\_endpoint\_dns\_servers) | List of DNS Servers for the VPN, defaults on the one of the VPC (see https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html) | `list(string)` | <pre>[<br/>  "169.254.169.253"<br/>]</pre> | no |
| <a name="input_vpn_name"></a> [vpn\_name](#input\_vpn\_name) | Name of the VPN | `string` | n/a | yes |
| <a name="input_vpn_session_timeout_hours"></a> [vpn\_session\_timeout\_hours](#input\_vpn\_session\_timeout\_hours) | Number of hours to timeout a session of the VPN connection | `number` | `8` | no |
| <a name="input_vpn_split_tunnel"></a> [vpn\_split\_tunnel](#input\_vpn\_split\_tunnel) | By default, when you have a Client VPN endpoint, all traffic from clients is routed over the Client VPN tunnel. When you enable split-tunnel on the Client VPN endpoint, we push the routes on the Client VPN endpoint route table to the device that is connected to the Client VPN endpoint. This ensures that only traffic with a destination to the network matching a route from the Client VPN endpoint route table is routed over the Client VPN tunnel. | `bool` | `false` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_vpn_ca_keys_s3_urls"></a> [vpn\_ca\_keys\_s3\_urls](#output\_vpn\_ca\_keys\_s3\_urls) | Map of S3 URLs for client private and public keys |
| <a name="output_vpn_client_configs"></a> [vpn\_client\_configs](#output\_vpn\_client\_configs) | Map of OpenVPN configs of each client |
| <a name="output_vpn_client_keys_s3_urls"></a> [vpn\_client\_keys\_s3\_urls](#output\_vpn\_client\_keys\_s3\_urls) | Map of S3 URLs for client private and public keys |
| <a name="output_vpn_endpoint"></a> [vpn\_endpoint](#output\_vpn\_endpoint) | Endpoint of the VPN |
| <a name="output_vpn_server_keys_s3_urls"></a> [vpn\_server\_keys\_s3\_urls](#output\_vpn\_server\_keys\_s3\_urls) | Map of S3 URLs for client private and public keys |
<!-- END_TF_DOCS -->
