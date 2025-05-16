# vpn

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_kms_key.certs_encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_object.upload_ca_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_ca_public_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_client_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.upload_client_public_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [null_resource.cleanup_downloaded_ca_files](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.download_existing_ca](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.wait_for_ca_download](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [tls_cert_request.client_csr](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/cert_request) | resource |
| [tls_locally_signed_cert.client_public_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/locally_signed_cert) | resource |
| [tls_private_key.ca_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.client_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.ca_public_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [local_file.existing_ca_cert](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.existing_ca_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ca_common_name"></a> [ca\_common\_name](#input\_ca\_common\_name) | Common Name (CN) field for the CA certificate | `string` | `"Local CA VPN"` | no |
| <a name="input_ca_early_renewal_hours"></a> [ca\_early\_renewal\_hours](#input\_ca\_early\_renewal\_hours) | Time before CA certificate expiration to renew it, in hours (default: 30 days) | `number` | `720` | no |
| <a name="input_ca_key_algorithm"></a> [ca\_key\_algorithm](#input\_ca\_key\_algorithm) | Algorithm used to generate the CA private key | `string` | `"RSA"` | no |
| <a name="input_ca_key_bits"></a> [ca\_key\_bits](#input\_ca\_key\_bits) | Key size in bits for the CA private key | `number` | `4096` | no |
| <a name="input_ca_organization"></a> [ca\_organization](#input\_ca\_organization) | Organization name for the CA certificate | `string` | `"Organization CA VPN"` | no |
| <a name="input_ca_validity_period_hours"></a> [ca\_validity\_period\_hours](#input\_ca\_validity\_period\_hours) | Validity period of the CA certificate in hours (default: 10 years) | `number` | `87600` | no |
| <a name="input_client_certificate_validity_period_hours"></a> [client\_certificate\_validity\_period\_hours](#input\_client\_certificate\_validity\_period\_hours) | Validity period of client certificates in hours (default: 1 year) | `number` | `8760` | no |
| <a name="input_client_key_algorithm"></a> [client\_key\_algorithm](#input\_client\_key\_algorithm) | Algorithm used to generate client private keys | `string` | `"RSA"` | no |
| <a name="input_client_key_bits"></a> [client\_key\_bits](#input\_client\_key\_bits) | Key size in bits for client private keys | `number` | `4096` | no |
| <a name="input_client_key_names"></a> [client\_key\_names](#input\_client\_key\_names) | List of client key names to generate certificates for | `list(string)` | n/a | yes |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Name of the KMS key used for encrypting certificates and keys in S3 | `string` | `"vpn-certs-kms-key"` | no |
| <a name="input_s3_bucket_name"></a> [s3\_bucket\_name](#input\_s3\_bucket\_name) | Name of the bucket that stores the certificates and keys | `string` | n/a | yes |
| <a name="input_s3_ca_directory"></a> [s3\_ca\_directory](#input\_s3\_ca\_directory) | Directory name inside the S3 bucket where CA and certificates are stored | `string` | `"my-ca"` | no |
## Outputs

No outputs.
<!-- END_TF_DOCS -->
