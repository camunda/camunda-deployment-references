# Import the locally generated certificates in AWS

resource "null_resource" "download_server_and_ca_certs" {
  depends_on = [
    aws_s3_object.upload_server_private_key,
    aws_s3_object.upload_server_public_key,
    aws_s3_object.upload_ca_private_key,
    aws_s3_object.upload_ca_public_key
  ]

  provisioner "local-exec" {
    when    = create
    command = <<EOT
      aws s3 cp s3://${var.s3_bucket_name}/${local.server_private_key_object_key} ${path.module}/server-key.pem
      aws s3 cp s3://${var.s3_bucket_name}/${local.server_public_key_object_key} ${path.module}/server-cert.pem
      aws s3 cp s3://${var.s3_bucket_name}/${local.ca_private_key_object_key} ${path.module}/ca-key.pem
      aws s3 cp s3://${var.s3_bucket_name}/${local.ca_public_key_object_key} ${path.module}/ca-cert.pem
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "wait_for_cert_download" {
  depends_on = [null_resource.download_server_and_ca_certs]

  triggers = {
    wait_for_file = timestamp()
  }
}

data "local_file" "server_private_key" {
  filename   = "${path.module}/server-key.pem"
  depends_on = [null_resource.wait_for_cert_download]
}

data "local_file" "server_cert" {
  filename   = "${path.module}/server-cert.pem"
  depends_on = [null_resource.wait_for_cert_download]
}

data "local_file" "ca_private_key" {
  filename   = "${path.module}/ca-key.pem"
  depends_on = [null_resource.wait_for_cert_download]
}

data "local_file" "ca_cert" {
  filename   = "${path.module}/ca-cert.pem"
  depends_on = [null_resource.wait_for_cert_download]
}

resource "null_resource" "cleanup_downloaded_certs" {
  depends_on = [
    data.local_file.server_private_key,
    data.local_file.server_cert,
    data.local_file.ca_private_key,
    data.local_file.ca_cert,
  ]

  provisioner "local-exec" {
    command = <<EOT
      rm -f ${path.module}/server-key.pem
      rm -f ${path.module}/server-cert.pem
      rm -f ${path.module}/ca-key.pem
      rm -f ${path.module}/ca-cert.pem
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}


resource "aws_acm_certificate" "vpn_cert" {
  provider = aws.vpn

  private_key       = data.local_file.server_private_key.content
  certificate_body  = data.local_file.server_cert.content
  certificate_chain = data.local_file.ca_cert.content
}

resource "aws_acm_certificate" "ca_cert" {
  provider = aws.vpn

  private_key      = data.local_file.ca_private_key.content
  certificate_body = data.local_file.ca_cert.content
}
