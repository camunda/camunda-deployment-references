# Download certs
resource "null_resource" "download_certs" {

  depends_on = [
    aws_s3_object.upload_client_private_key,
    aws_s3_object.upload_client_public_key,
  ]
  provisioner "local-exec" {
    when    = "create"
    command = <<EOT
mkdir -p ${path.module}/certs
%{for client in var.client_key_names~}
aws s3 cp s3://${var.s3_bucket_name}/${local.client_keys[client].private_key_object_key} ${path.module}/certs/${client}.crt
aws s3 cp s3://${var.s3_bucket_name}/${local.client_keys[client].public_key_object_key} ${path.module}/certs/${client}.key
%{endfor~}
EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "wait_for_cert_download_client" {
  depends_on = [null_resource.download_certs]

  triggers = {
    wait_for_file = timestamp()
  }
}

# Load certs

data "local_file" "client_cert" {
  for_each   = toset(var.client_key_names)
  filename   = "${path.module}/certs/${each.key}.crt"
  depends_on = [null_resource.wait_for_cert_download_client]
}

data "local_file" "client_key" {
  for_each   = toset(var.client_key_names)
  filename   = "${path.module}/certs/${each.key}.key"
  depends_on = [null_resource.wait_for_cert_download_client]
}


# Generate a config file for each client
resource "local_file" "vpn_config" {
  for_each = toset(var.client_key_names)

  filename = "${path.module}/client-configs/${each.key}.ovpn"

  content = <<-EOT
client
dev tun
proto udp
remote ${aws_ec2_client_vpn_endpoint.vpn.dns_name} 443
remote-random-hostname
resolv-retry infinite
nobind
remote-cert-tls server
cipher AES-256-GCM
verify-x509-name ${var.server_common_name} name
reneg-sec 0
verb 3

<ca>
${data.local_file.ca_cert.content}
</ca>

<cert>
${data.local_file.client_cert[each.key].content}
</cert>

<key>
${data.local_file.client_key[each.key].content}
</key>
EOT

  file_permission = "0600"

  depends_on = [
    aws_ec2_client_vpn_endpoint.vpn,
    null_resource.wait_for_cert_download_client
  ]
}

# Cleanup certs
resource "null_resource" "cleanup_certs" {
  depends_on = [local_file.vpn_config]

  provisioner "local-exec" {
    command = "rm -rf ${path.module}/certs"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "aws_s3_object" "upload_vpn_config" {
  provider = aws.bucket


  for_each               = local_file.vpn_config
  bucket                 = var.s3_bucket_name
  key                    = "${var.s3_ca_directory}/client-configs/${each.key}.ovpn"
  content                = each.value.content
  kms_key_id             = aws_kms_key.certs_encryption.arn
  server_side_encryption = "aws:kms"
  content_type           = "text/plain"
  acl                    = "private"

  lifecycle {
    ignore_changes = [content]
  }
}

resource "null_resource" "cleanup_client_configs" {
  depends_on = [aws_s3_object.upload_vpn_config]

  provisioner "local-exec" {
    command = "rm -rf ${path.module}/client-configs"
  }

  triggers = {
    always_run = timestamp()
  }
}
