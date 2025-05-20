# KMS

resource "aws_kms_key" "certs_encryption" {
  provider = aws.bucket

  description             = "KMS key for encrypting VPN certs in S3"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = var.kms_key_name
  }
}

# CA

locals {
  ca_private_key_object_key = "${var.s3_ca_directory}/ca-key.pem"
  ca_public_key_object_key  = "${var.s3_ca_directory}/ca-key.pub.pem"

  server_private_key_object_key = "${var.s3_ca_directory}/server-key.pem"
  server_public_key_object_key  = "${var.s3_ca_directory}/server-key.pub.pem"

  client_keys = {
    for name in var.client_key_names : name => {
      private_key_object_key = "${var.s3_ca_directory}/${name}-client-key.pem"
      public_key_object_key  = "${var.s3_ca_directory}/${name}-client-key.pub.pem"
    }
  }
}

resource "tls_private_key" "ca_private_key" {
  algorithm = var.ca_key_algorithm
  rsa_bits  = var.ca_key_bits
}

resource "tls_self_signed_cert" "ca_public_key" {
  private_key_pem = tls_private_key.ca_private_key.private_key_pem

  subject {
    common_name  = var.ca_common_name
    organization = var.ca_organization
  }

  is_ca_certificate     = true
  validity_period_hours = var.ca_validity_period_hours
  early_renewal_hours   = var.ca_early_renewal_hours

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

## Upload the CA in an S3 bucket

resource "aws_s3_object" "upload_ca_private_key" {
  provider = aws.bucket

  bucket                 = var.s3_bucket_name
  key                    = local.ca_private_key_object_key
  content                = tls_private_key.ca_private_key.private_key_pem
  kms_key_id             = aws_kms_key.certs_encryption.arn
  server_side_encryption = "aws:kms"
  content_type           = "text/plain"
  acl                    = "private"

  # if the cert already exists, we don't update it
  lifecycle {
    ignore_changes = [content]
  }
}

resource "aws_s3_object" "upload_ca_public_key" {
  provider = aws.bucket

  bucket       = var.s3_bucket_name
  key          = local.ca_public_key_object_key
  content      = tls_self_signed_cert.ca_public_key.cert_pem
  content_type = "text/plain"

  # if the cert already exists, we don't update it
  lifecycle {
    ignore_changes = [content]
  }
}

# Download the CA cert

resource "null_resource" "download_existing_ca" {

  depends_on = [
    aws_s3_object.upload_ca_private_key,
    aws_s3_object.upload_client_public_key
  ]

  provisioner "local-exec" {
    when    = create
    command = <<EOT
      aws s3 cp s3://${var.s3_bucket_name}/${local.ca_private_key_object_key} ./existing-ca-key.pem
      aws s3 cp s3://${var.s3_bucket_name}/${local.ca_public_key_object_key} ./existing-ca-cert.pem
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "wait_for_ca_download" {
  depends_on = [
    null_resource.download_existing_ca
  ]

  triggers = {
    wait_for_file = timestamp()
  }
}

data "local_file" "existing_ca_key" {
  filename = "${path.module}/existing-ca-key.pem"

  depends_on = [null_resource.wait_for_ca_download]
}

data "local_file" "existing_ca_cert" {
  filename = "${path.module}/existing-ca-cert.pem"

  depends_on = [null_resource.wait_for_ca_download]
}

resource "null_resource" "cleanup_downloaded_ca_files" {
  depends_on = [
    data.local_file.existing_ca_key,
    data.local_file.existing_ca_cert
  ]

  provisioner "local-exec" {
    command = <<EOT
      rm -f ${path.module}/existing-ca-key.pem
      rm -f ${path.module}/existing-ca-cert.pem
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}


# Server cert signed by the Root CA
resource "tls_private_key" "server_private_key" {
  algorithm = var.key_algorithm
  rsa_bits  = var.key_bits
}

resource "tls_cert_request" "server_csr" {
  private_key_pem = tls_private_key.server_private_key.private_key_pem

  subject {
    common_name = var.server_common_name
  }
}

resource "tls_locally_signed_cert" "server_public_key" {
  cert_request_pem   = tls_cert_request.server_csr.cert_request_pem
  ca_private_key_pem = tls_private_key.ca_private_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca_public_key.cert_pem

  validity_period_hours = var.server_certificate_validity_period_hours
  set_subject_key_id    = true

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

## Upload the signed certs using the S3 bucket

resource "aws_s3_object" "upload_server_private_key" {
  provider = aws.bucket

  bucket                 = var.s3_bucket_name
  key                    = local.server_private_key_object_key
  content                = tls_private_key.server_private_key.private_key_pem
  kms_key_id             = aws_kms_key.certs_encryption.arn
  server_side_encryption = "aws:kms"
  content_type           = "text/plain"
  acl                    = "private"

  # if the cert already exists, we don't update it
  lifecycle {
    ignore_changes = [content]
  }
}

resource "aws_s3_object" "upload_server_public_key" {
  provider = aws.bucket

  bucket  = var.s3_bucket_name
  key     = local.server_public_key_object_key
  content = tls_locally_signed_cert.server_public_key.cert_pem

  content_type = "text/plain"

  lifecycle {
    ignore_changes = [content]
  }
}

# Client cert signed by the Root CA
resource "tls_private_key" "client_private_key" {
  for_each  = local.client_keys
  algorithm = var.key_algorithm
  rsa_bits  = var.key_bits
}

resource "tls_cert_request" "client_csr" {
  for_each = tls_private_key.client_private_key

  private_key_pem = each.value.private_key_pem

  subject {
    common_name = "${var.ca_common_name}.${each.key}"
  }
}

resource "tls_locally_signed_cert" "client_public_key" {
  for_each           = tls_cert_request.client_csr
  cert_request_pem   = each.value.cert_request_pem
  ca_private_key_pem = tls_private_key.ca_private_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca_public_key.cert_pem

  validity_period_hours = var.client_certificate_validity_period_hours
  set_subject_key_id    = true

  allowed_uses = [
    "client_auth",
    "digital_signature",
  ]
}

## Upload the signed certs using the S3 bucket


resource "aws_s3_object" "upload_client_private_key" {
  provider = aws.bucket

  for_each               = tls_private_key.client_private_key
  bucket                 = var.s3_bucket_name
  key                    = local.client_keys[each.key].private_key_object_key
  content                = each.value.private_key_pem
  kms_key_id             = aws_kms_key.certs_encryption.arn
  server_side_encryption = "aws:kms"
  content_type           = "text/plain"
  acl                    = "private"

  # if the cert already exists, we don't update it
  lifecycle {
    ignore_changes = [content]
  }
}

resource "aws_s3_object" "upload_client_public_key" {
  provider = aws.bucket

  for_each     = tls_locally_signed_cert.client_public_key
  bucket       = var.s3_bucket_name
  key          = local.client_keys[each.key].public_key_object_key
  content      = each.value.cert_pem
  content_type = "text/plain"

  lifecycle {
    ignore_changes = [content]
  }
}
