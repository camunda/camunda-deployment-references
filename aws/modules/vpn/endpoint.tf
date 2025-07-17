# Create Client VPN Endpoint

resource "aws_security_group" "vpn" {
  name_prefix = "client-vpn-endpoint-sg-${var.vpn_name}"
  description = "Security group for Client VPN endpoint ${var.vpn_name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow client VPN connections from approved IP ranges"
    from_port   = 443
    to_port     = 443
    protocol    = "udp"
    cidr_blocks = var.vpn_allowed_cidr_blocks
  }

  egress {
    description = "Allow the VPN to access the internal network, unrestricted"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_target_network_cidr]
  }
}

resource "aws_ec2_client_vpn_endpoint" "vpn" {
  description            = "Client VPN endpoint of ${var.vpn_name}"
  server_certificate_arn = aws_acm_certificate.vpn_cert.arn
  client_cidr_block      = var.vpn_client_cidr
  vpc_id                 = var.vpc_id
  split_tunnel           = var.vpn_split_tunnel

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.ca_cert.arn
  }

  transport_protocol = "udp"
  security_group_ids = [aws_security_group.vpn.id]

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn_logs.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn_logs.name
  }

  dns_servers = var.vpn_endpoint_dns_servers

  session_timeout_hours = var.vpn_session_timeout_hours

  client_login_banner_options {
    enabled     = true
    banner_text = var.vpn_client_banner
  }

  tags = {
    Name = "client-vpn-${var.vpn_name}"
  }
}

# Associate to target network to the VPN

resource "aws_ec2_client_vpn_network_association" "vpn_subnet" {
  for_each = var.vpc_subnet_ids

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.vpn.id
  subnet_id              = each.value
}

resource "aws_ec2_client_vpn_authorization_rule" "vpn_auth_rule" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.vpn.id
  target_network_cidr    = var.vpc_target_network_cidr
  authorize_all_groups   = true

  timeouts {
    create = "15m"
    delete = "20m"
  }
}

# Logging
resource "aws_cloudwatch_log_group" "vpn_logs" {
  # encrypted by default
  name              = "/aws/vpn/${var.vpn_name}"
  retention_in_days = var.vpn_cloudwatch_log_group_retention
}

resource "aws_cloudwatch_log_stream" "vpn_logs" {
  name           = "vpn-connection-logs-${var.vpn_name}"
  log_group_name = aws_cloudwatch_log_group.vpn_logs.name
}
