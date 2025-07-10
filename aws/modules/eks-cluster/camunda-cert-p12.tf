variable "camunda_p12_password" {
  type        = string
  description = "Password for the Camunda .p12 certificate bundle"
  sensitive   = true
  default     = "NotVerySecurePassword123!"
}

# Export PEM files locally
resource "local_file" "camunda_key" {
  content  = tls_private_key.camunda_key.private_key_pem
  filename = "${path.module}/camunda_key.pem"
}

resource "local_file" "camunda_cert" {
  content  = aws_acmpca_certificate.camunda_signed_cert.certificate
  filename = "${path.module}/camunda_cert.pem"
}

resource "local_file" "sub_ca_cert" {
  content  = tls_locally_signed_cert.sub_ca_cert_signed.cert_pem
  filename = "${path.module}/sub_ca_cert.pem"
}

resource "local_file" "root_ca_cert" {
  content  = tls_self_signed_cert.root_ca_cert.cert_pem
  filename = "${path.module}/root_ca_cert.pem"
}

# Generate p12 using full chain: camunda -> subCA -> rootCA
resource "null_resource" "generate_camunda_p12" {
  provisioner "local-exec" {
    command = <<EOT
cat "${path.module}/sub_ca_cert.pem" "${path.module}/root_ca_cert.pem" > "${path.module}/chain.pem"

openssl pkcs12 -export \
  -inkey "${path.module}/camunda_key.pem" \
  -in "${path.module}/camunda_cert.pem" \
  -certfile "${path.module}/chain.pem" \
  -out "${path.module}/camunda_bundle.p12" \
  -passout pass:${var.camunda_p12_password}
EOT
  }

  triggers = {
    cert         = aws_acmpca_certificate.camunda_signed_cert.certificate
    key          = tls_private_key.camunda_key.private_key_pem
    ca           = tls_locally_signed_cert.sub_ca_cert_signed.cert_pem
    root         = tls_self_signed_cert.root_ca_cert.cert_pem
    password     = var.camunda_p12_password
    always_regen = timestamp()
  }

  depends_on = [
    local_file.camunda_key,
    local_file.camunda_cert,
    local_file.sub_ca_cert,
    local_file.root_ca_cert
  ]
}

# Store the .p12 in AWS Secrets Manager
resource "aws_secretsmanager_secret" "camunda_p12_secret" {
  name        = "certs/${local.camunda_custom_domain}/certificate-p12"
  description = "PKCS#12 bundle for Camunda ${local.camunda_custom_domain}"
}

# Upload the p12 using AWS CLI
resource "null_resource" "upload_p12_to_secretsmanager" {
  depends_on = [
    null_resource.generate_camunda_p12,
    aws_secretsmanager_secret.camunda_p12_secret
  ]

  provisioner "local-exec" {
    command = <<EOT
aws secretsmanager put-secret-value \
  --secret-id "certs/${local.camunda_custom_domain}/certificate-p12" \
  --secret-binary fileb://${path.module}/camunda_bundle.p12 \
  --region ${var.region}
EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "aws_secretsmanager_secret" "camunda_p12_password_secret" {
  name        = "certs/${local.camunda_custom_domain}/p12-password"
  description = "Password for the Camunda PKCS#12 bundle"
}

resource "aws_secretsmanager_secret_version" "camunda_p12_password_secret_version" {
  secret_id     = aws_secretsmanager_secret.camunda_p12_password_secret.id
  secret_string = var.camunda_p12_password
}

resource "null_resource" "convert_p12_to_jks" {
  depends_on = [null_resource.generate_camunda_p12]

  provisioner "local-exec" {
    command = <<EOT
keytool -importkeystore \
  -srckeystore "${path.module}/camunda_bundle.p12" \
  -srcstoretype PKCS12 \
  -srcstorepass "${var.camunda_p12_password}" \
  -destkeystore "${path.module}/camunda_keystore.jks" \
  -deststoretype JKS \
  -deststorepass "${var.camunda_p12_password}" \
  -noprompt
EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "aws_secretsmanager_secret" "camunda_jks_secret" {
  name        = "certs/${local.camunda_custom_domain}/keystore-jks"
  description = "JKS keystore for Camunda ${local.camunda_custom_domain}"
}

resource "null_resource" "upload_jks_to_secretsmanager" {
  depends_on = [
    null_resource.convert_p12_to_jks,
    aws_secretsmanager_secret.camunda_jks_secret
  ]

  provisioner "local-exec" {
    command = <<EOT
aws secretsmanager put-secret-value \
  --secret-id "certs/${local.camunda_custom_domain}/keystore-jks" \
  --secret-binary fileb://${path.module}/camunda_keystore.jks \
  --region ${var.region}
EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "download_certificates" {
  provisioner "local-exec" {
    command = <<EOT
mkdir -p "${path.module}/certificates"
curl -o "${path.module}/certificates/AmazonRootCA1.pem" https://www.amazontrust.com/repository/AmazonRootCA1.pem
curl -o "${path.module}/certificates/AmazonRootCA2.pem" https://www.amazontrust.com/repository/AmazonRootCA2.pem
curl -o "${path.module}/certificates/AmazonRootCA3.pem" https://www.amazontrust.com/repository/AmazonRootCA3.pem
curl -o "${path.module}/certificates/AmazonRootCA4.pem" https://www.amazontrust.com/repository/AmazonRootCA4.pem
curl -o "${path.module}/certificates/SFSRootCAG2.pem" https://www.amazontrust.com/repository/SFSRootCAG2.pem
EOT
  }
}


resource "null_resource" "generate_truststore_jks" {
  depends_on = [
    local_file.sub_ca_cert,
    local_file.root_ca_cert,
    null_resource.download_certificates
  ]

  provisioner "local-exec" {
    command = <<EOT
keytool -import \
  -alias rootca \
  -trustcacerts \
  -file "${path.module}/root_ca_cert.pem" \
  -keystore "${path.module}/camunda_truststore.jks" \
  -storepass "${var.camunda_p12_password}" \
  -noprompt

keytool -import \
  -alias subca \
  -trustcacerts \
  -file "${path.module}/sub_ca_cert.pem" \
  -keystore "${path.module}/camunda_truststore.jks" \
  -storepass "${var.camunda_p12_password}" \
  -noprompt

keytool -import \
  -alias amazonrootca1 \
  -trustcacerts \
  -file "${path.module}/certificates/AmazonRootCA1.pem" \
  -keystore "${path.module}/camunda_truststore.jks" \
  -storepass "${var.camunda_p12_password}" \
  -noprompt

keytool -import \
  -alias amazonrootca2 \
  -trustcacerts \
  -file "${path.module}/certificates/AmazonRootCA2.pem" \
  -keystore "${path.module}/camunda_truststore.jks" \
  -storepass "${var.camunda_p12_password}" \
  -noprompt

keytool -import \
  -alias amazonrootca3 \
  -trustcacerts \
  -file "${path.module}/certificates/AmazonRootCA3.pem" \
  -keystore "${path.module}/camunda_truststore.jks" \
  -storepass "${var.camunda_p12_password}" \
  -noprompt

keytool -import \
  -alias amazonrootca4 \
  -trustcacerts \
  -file "${path.module}/certificates/AmazonRootCA4.pem" \
  -keystore "${path.module}/camunda_truststore.jks" \
  -storepass "${var.camunda_p12_password}" \
  -noprompt

keytool -import \
  -alias sfsrootcag2 \
  -trustcacerts \
  -file "${path.module}/certificates/SFSRootCAG2.pem" \
  -keystore "${path.module}/camunda_truststore.jks" \
  -storepass "${var.camunda_p12_password}" \
  -noprompt
EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "aws_secretsmanager_secret" "camunda_truststore_secret" {
  name        = "certs/${local.camunda_custom_domain}/truststore-jks"
  description = "JKS truststore for Camunda ${local.camunda_custom_domain}"
}

resource "null_resource" "upload_truststore_to_secretsmanager" {
  depends_on = [
    null_resource.generate_truststore_jks,
    aws_secretsmanager_secret.camunda_truststore_secret
  ]

  provisioner "local-exec" {
    command = <<EOT
aws secretsmanager put-secret-value \
  --secret-id "certs/${local.camunda_custom_domain}/truststore-jks" \
  --secret-binary fileb://${path.module}/camunda_truststore.jks \
  --region ${var.region}
EOT
  }

  triggers = {
    always_run = timestamp()
  }
}
